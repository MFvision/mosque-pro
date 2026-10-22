import Foundation

/// Ayah of the day and Hadith of the day, from shared/daily/daily.json (built by tools/build_daily.py). Everyone
/// sees the same verse and hadith on the same calendar date. Mirrors android/core DailyContent.kt; both are checked
/// against shared/fixtures/daily.json.
public struct DailyContent: Decodable, Sendable {
    public struct SurahName: Decodable, Hashable, Sendable {
        public let ar: String
        public let en: String
        public let translit: String
    }

    public struct Ayah: Decodable, Hashable, Sendable {
        /// "2:255" or "94:5-6".
        public let ref: String
        public let surah: Int
        public let first: Int
        public let last: Int
        public let surahName: SurahName
        /// The Arabic text, with each verse's number in ornate brackets.
        public let ar: String
        /// Translation by language code (en, es, fr, id, tr, ur).
        public let translations: [String: String]

        /// The translation for this language, or English when there is none.
        public func translation(_ lang: String) -> String? {
            lang == "ar" ? nil : translations[lang] ?? translations["en"]
        }
    }

    public struct HadithText: Decodable, Hashable, Sendable {
        public let text: String
        public let grade: String
        public let source: String
    }

    public struct Hadith: Decodable, Hashable, Sendable {
        /// HadeethEnc's item number.
        public let id: Int
        public let ar: HadithText
        public let translations: [String: HadithText]
        public let url: String

        /// The hadith in this language (Arabic for ar), or English when there is none.
        public func text(_ lang: String) -> HadithText {
            lang == "ar" ? ar : translations[lang] ?? translations["en"] ?? ar
        }
    }

    public let epoch: String
    public let ayat: [Ayah]
    public let hadith: [Hadith]

    public static func load(_ data: Data) throws -> DailyContent {
        try JSONDecoder().decode(DailyContent.self, from: data)
    }

    /// The verse for a calendar date (year, month, day as the person's calendar shows it).
    public func ayah(year: Int, month: Int, day: Int) -> Ayah {
        ayat[Self.index(year: year, month: month, day: day, count: ayat.count)]
    }

    public func hadith(year: Int, month: Int, day: Int) -> Hadith {
        hadith[Self.index(year: year, month: month, day: day, count: hadith.count)]
    }

    public func ayah(for date: Date, calendar: Calendar = .current) -> Ayah {
        let d = Self.gregorian(date, calendar.timeZone)
        return ayah(year: d.year, month: d.month, day: d.day)
    }

    public func hadith(for date: Date, calendar: Calendar = .current) -> Hadith {
        let d = Self.gregorian(date, calendar.timeZone)
        return hadith(year: d.year, month: d.month, day: d.day)
    }

    /// Whole days since 2026-01-01, wrapped to the list (dates before it wrap backwards).
    public static func index(year: Int, month: Int, day: Int, count: Int) -> Int {
        precondition(count > 0)
        let days = daysFromCivil(year, month, day) - daysFromCivil(2026, 1, 1)
        return ((days % count) + count) % count
    }

    /// The date in the Gregorian calendar, whatever calendar the person uses, so a Hijri calendar setting picks the
    /// same entry as everyone else on that day.
    static func gregorian(_ date: Date, _ zone: TimeZone) -> (year: Int, month: Int, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    /// Days since 1970-01-01 for a Gregorian date (Howard Hinnant's days_from_civil).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
