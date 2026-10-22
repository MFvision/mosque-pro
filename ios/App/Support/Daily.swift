import Foundation
import NMCore

/// Ayah of the day and Hadith of the day, from the bundled shared/daily/daily.json (nil if the file is missing).
enum Daily {
    static let content: DailyContent? = Bundle.main.url(forResource: "daily", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? DailyContent.load($0) }

    /// The reference under a verse: the surah's name in the interface language (Arabic or English) and the verse numbers.
    static func reference(_ a: DailyContent.Ayah, language: String, locale: Locale) -> String {
        let name = language == "ar" ? a.surahName.ar : a.surahName.translit
        let nums = a.first == a.last ? number(a.first, locale) : "\(number(a.first, locale))–\(number(a.last, locale))"
        return "\(name) \(number(a.surah, locale)):\(nums)"
    }

    private static func number(_ n: Int, _ locale: Locale) -> String {
        n.formatted(.number.grouping(.never).locale(locale))
    }
}
