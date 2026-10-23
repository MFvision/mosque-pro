import Foundation
import XCTest
@testable import NMCore

final class HelpCenterTests: XCTestCase {
    let help = try! HelpCenter.load(Data(contentsOf: Fixtures.root.appendingPathComponent("shared/help/help.json")))

    func testSearchMatchesSharedFixture() {
        let f = Fixtures.json("shared/fixtures/help-search.json")
        for c in f["cases"] as! [[String: Any]] {
            let platform = HelpCenter.Platform(rawValue: c["platform"] as! String)!
            let query = c["query"] as! String
            XCTAssertEqual(help.search(query, platform: platform).map(\.id), c["ids"] as? [String], "\(platform) \(query)")
        }
    }

    func testLanguagesAndPlatforms() {
        let a = help.articles[0]
        XCTAssertEqual(a.title("ar"), a.title.ar)
        XCTAssertEqual(a.title("fr"), a.title.en)
        XCTAssertFalse(help.articles(for: .tv).contains { $0.id == "clean-network" })
        XCTAssertTrue(help.articles(for: .phone).contains { $0.id == "clean-network" })
        XCTAssertTrue(help.contact.email.contains("@"))
    }

    /// A fixed sequence, so a reference can be checked letter by letter.
    struct Counter: RandomNumberGenerator {
        var n: UInt64 = 0
        mutating func next() -> UInt64 { n &+= 0x9E37_79B9_7F4A_7C15; return n }
    }

    func testReference() {
        var a = Counter(), b = Counter()
        let ref = SupportRequest.newReference(using: &a)
        XCTAssertEqual(ref, SupportRequest.newReference(using: &b))
        XCTAssertTrue(ref.hasPrefix("MP-"))
        XCTAssertEqual(ref.count, 9)
        // No 0/O, 1/I/L: a reference read aloud or typed back can't be mistaken.
        XCTAssertTrue(ref.dropFirst(3).allSatisfy { SupportRequest.alphabet.contains($0) })
        XCTAssertFalse(SupportRequest.alphabet.contains { "01OIL".contains($0) })
        XCTAssertNotEqual(SupportRequest.newReference(), SupportRequest.newReference())
    }

    func request(_ message: String, details: [String] = ["App: 1.0.0 (152)", "Device: iPhone17,1 · iOS 26.1"]) -> SupportRequest {
        SupportRequest(id: "MP-7K4Q2X", kind: .problem, message: message, details: details,
                       sent: Date(timeIntervalSince1970: 1_793_000_000), channel: .email)
    }

    func testBodyCarriesReferenceAndDetails() {
        let r = request("  الأذان لا يعمل بعد التحديث\n")
        XCTAssertEqual(r.subject(kindTitle: "مشكلة", appName: "مسجد وأكثر"), "[MP-7K4Q2X] مشكلة · مسجد وأكثر")
        XCTAssertEqual(r.body, "الأذان لا يعمل بعد التحديث\n\n—\nRef: MP-7K4Q2X\nType: problem\nApp: 1.0.0 (152)\nDevice: iPhone17,1 · iOS 26.1")
        XCTAssertFalse(request("x", details: []).body.contains("App:"))
    }

    func testLinksSurviveAnyMessage() throws {
        // & = + # ? in a message must not cut the link short or add fields to it.
        let r = request("Fajr & Isha = wrong + late #1? 100%")
        let mail = try XCTUnwrap(r.mailURL(to: "app@vision.bz", subject: r.subject(kindTitle: "Problem", appName: "Mosque Pro")))
        XCTAssertEqual(mail.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "app@vision.bz")
        XCTAssertEqual(parts.queryItems?.map(\.name), ["subject", "body"])
        XCTAssertEqual(parts.queryItems?.last?.value, r.body)
    }

    func testHistoryKeepsNewestFirstAndRoundTrips() {
        var list: [SupportRequest] = []
        // Sent with WhatsApp, before it was taken out: such requests still load.
        for i in 0..<5 {
            let r = SupportRequest(id: "MP-AAAAA\(i + 2)", kind: .idea, message: "idea \(i)", details: [],
                                   sent: Date(timeIntervalSince1970: Double(1_793_000_000 + i)), channel: .whatsapp)
            list = SupportRequest.adding(r, to: list, limit: 3)
        }
        XCTAssertEqual(list.map(\.message), ["idea 4", "idea 3", "idea 2"])
        XCTAssertEqual(SupportRequest.decodeList(SupportRequest.encodeList(list)), list)
        XCTAssertEqual(SupportRequest.decodeList(nil), [])
        XCTAssertEqual(SupportRequest.decodeList(Data("not json".utf8)), [])
    }
}
