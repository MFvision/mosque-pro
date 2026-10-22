import Foundation
import XCTest
@testable import NMCore

final class DailyContentTests: XCTestCase {
    let daily = try! DailyContent.load(Data(contentsOf: Fixtures.root.appendingPathComponent("shared/daily/daily.json")))

    func testSharedFixture() {
        let f = Fixtures.json("shared/fixtures/daily.json")
        XCTAssertEqual(daily.ayat.count, f["ayatCount"] as? Int)
        XCTAssertEqual(daily.hadith.count, f["hadithCount"] as? Int)
        for c in f["cases"] as! [[String: Any]] {
            let p = (c["date"] as! String).split(separator: "-").map { Int($0)! }
            XCTAssertEqual(DailyContent.index(year: p[0], month: p[1], day: p[2], count: daily.ayat.count), c["ayahIndex"] as? Int)
            XCTAssertEqual(daily.ayah(year: p[0], month: p[1], day: p[2]).ref, c["ayahRef"] as? String, "\(c["date"]!)")
            XCTAssertEqual(daily.hadith(year: p[0], month: p[1], day: p[2]).id, c["hadithId"] as? Int, "\(c["date"]!)")
        }
    }

    func testLocalDateDecides() {
        // 23:30 on 1 January in Riyadh is still 1 January there, though it is 2 January in Tokyo.
        let instant = ISO8601DateFormatter().date(from: "2026-01-01T20:30:00Z")!
        var riyadh = Calendar(identifier: .islamicUmmAlQura)
        riyadh.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(daily.ayah(for: instant, calendar: riyadh).ref, daily.ayat[0].ref)
        XCTAssertEqual(daily.ayah(for: instant, calendar: tokyo).ref, daily.ayat[1].ref)
    }

    func testLanguages() {
        let a = daily.ayat[0], h = daily.hadith[0]
        XCTAssertNil(a.translation("ar"))
        XCTAssertEqual(a.translation("zz"), a.translations["en"])
        XCTAssertEqual(h.text("ar"), h.ar)
        XCTAssertEqual(h.text("zz"), h.translations["en"])
        XCTAssertTrue(daily.hadith.allSatisfy { ["صحيح", "حسن"].contains($0.ar.grade) })
    }
}
