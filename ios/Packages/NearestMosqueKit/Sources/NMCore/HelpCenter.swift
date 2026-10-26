import Foundation

/// The Help Center: answers to common problems from shared/help/help.json (English and Arabic; other interface
/// languages read English), found by a search in either language. Checked with tools/check_help.py against
/// shared/fixtures/help-search.json.
public struct HelpCenter: Decodable, Sendable {
    /// phone: iPhone, iPad, Mac and Apple Vision Pro. tv: Apple TV.
    public enum Platform: String, Decodable, Sendable { case phone, tv }

    public struct Text: Decodable, Hashable, Sendable {
        public let en: String
        public let ar: String

        /// Arabic for an Arabic interface, else English.
        public func callAsFunction(_ language: String) -> String { language == "ar" ? ar : en }
    }

    public struct Keywords: Decodable, Hashable, Sendable {
        public let en: [String]
        public let ar: [String]
    }

    public struct Article: Decodable, Hashable, Identifiable, Sendable {
        public let id: String
        public let platforms: [Platform]
        public let title: Text
        public let body: Text
        public let keywords: Keywords
    }

    public struct Contact: Decodable, Hashable, Sendable {
        public let email: String

        public init(email: String) {
            self.email = email
        }
    }

    public let contact: Contact
    public let articles: [Article]

    public static func load(_ data: Data) throws -> HelpCenter {
        try JSONDecoder().decode(HelpCenter.self, from: data)
    }

    public func articles(for platform: Platform) -> [Article] {
        articles.filter { $0.platforms.contains(platform) }
    }

    /// Words too common to tell the answers apart (normalized like the query).
    static let stopwords: Set<String> = Set(TextNormalizer.tokens(
        "the a an my i is are to of in on and or how do does what why it it's can't don't doesn't won't app me with for "
            + "ما في من على لا كيف هل عن إلى الى أن ان لماذا لم هذا التطبيق عندي"))

    /// The answers for a search, best first: a query word in an answer's title or keywords counts 3, the start of one
    /// (three letters or more) 2, a word of its text 1; ties keep the file's order. Words match in either language, so
    /// an Arabic search finds answers on an English screen. An empty search lists every answer.
    public func search(_ query: String, platform: Platform) -> [Article] {
        let words = TextNormalizer.tokens(query).filter { !Self.stopwords.contains($0) }
        let list = articles(for: platform)
        guard !words.isEmpty else { return list }
        var scored: [(score: Int, index: Int, article: Article)] = []
        for (i, a) in list.enumerated() {
            let strong = Set(TextNormalizer.tokens([a.title.en, a.title.ar, a.keywords.en.joined(separator: " "),
                                                    a.keywords.ar.joined(separator: " ")].joined(separator: " ")))
            let weak = Set(TextNormalizer.tokens(a.body.en + " " + a.body.ar))
            var score = 0
            for w in words {
                if strong.contains(w) {
                    score += 3
                } else if w.unicodeScalars.count >= 3, strong.contains(where: { $0.hasPrefix(w) }) {
                    score += 2
                } else if weak.contains(w) {
                    score += 1
                }
            }
            if score > 0 { scored.append((score, i, a)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.article)
    }
}

/// What a person sends us from the Help Center: a problem, an idea or a question, with a reference to quote and,
/// if they leave them in, a few lines about the app and the device (never the location). There is no server yet: it goes
/// by email, and the app keeps a copy so the person can see what they sent and quote the reference.
public struct SupportRequest: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case problem, idea, question }

    /// How it left the device. WhatsApp is no longer offered; the case stays so requests sent with it still load.
    public enum Channel: String, Codable, Sendable { case email, whatsapp, copied }

    /// The reference, "MP-" and six letters or digits that can't be mistaken for each other.
    public let id: String
    public let kind: Kind
    public let message: String
    /// "App: 1.0.0 (152)" and the like; empty when the person took them out.
    public let details: [String]
    public let sent: Date
    public var channel: Channel

    public init(id: String, kind: Kind, message: String, details: [String], sent: Date, channel: Channel) {
        self.id = id; self.kind = kind; self.message = message; self.details = details; self.sent = sent; self.channel = channel
    }

    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    public static func newReference<G: RandomNumberGenerator>(using rng: inout G) -> String {
        "MP-" + String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    public static func newReference() -> String {
        var rng = SystemRandomNumberGenerator()
        return newReference(using: &rng)
    }

    /// "[MP-7K4Q2X] Problem · Mosque Pro": the kind as the person's interface names it.
    public func subject(kindTitle: String, appName: String) -> String {
        "[\(id)] \(kindTitle) · \(appName)"
    }

    /// The message, then the reference and the details under a rule, so a reply can quote the reference.
    public var body: String {
        var lines = [message.trimmingCharacters(in: .whitespacesAndNewlines), "", "—", "Ref: \(id)", "Type: \(kind.rawValue)"]
        lines += details
        return lines.joined(separator: "\n")
    }

    /// Characters left as they are in a link's query; everything else is percent-encoded (& = + # included, so the
    /// message can't break the link).
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }

    public func mailURL(to email: String, subject: String) -> URL? {
        URL(string: "mailto:\(email)?subject=\(Self.encode(subject))&body=\(Self.encode(body))")
    }

    /// The person's sent requests, newest first, at most `limit` (older ones drop off).
    public static func adding(_ r: SupportRequest, to list: [SupportRequest], limit: Int = 50) -> [SupportRequest] {
        Array(([r] + list.filter { $0.id != r.id }).prefix(limit))
    }

    public static func decodeList(_ data: Data?) -> [SupportRequest] {
        guard let data, let list = try? decoder.decode([SupportRequest].self, from: data) else { return [] }
        return list
    }

    public static func encodeList(_ list: [SupportRequest]) -> Data {
        (try? encoder.encode(list)) ?? Data()
    }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
