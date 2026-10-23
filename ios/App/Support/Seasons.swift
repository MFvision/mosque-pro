import Foundation
import NMCore

/// Ramadan and Friday on the prayer screens: the greeting, what the next prayer means that day (the iftar, the end
/// of suhoor, going early to the Jumu'ah, the last hour of Friday) and when Surah Al-Kahf is read. Months are Umm
/// al-Qura's with the user's Hijri adjustment, as the dates shown elsewhere.
enum Seasons {
    static func hijri(_ instant: Date, zone: TimeZone, adjustment: Int) -> HijriCalendar.HijriDate? {
        HijriCalendar.of(CivilDate.of(instant, in: zone), adjustmentDays: adjustment)
    }

    static func isRamadan(_ instant: Date, zone: TimeZone, adjustment: Int) -> Bool {
        hijri(instant, zone: zone, adjustment: adjustment)?.month == 9
    }

    /// 1 is Sunday, 5 Thursday, 6 Friday.
    static func weekday(_ instant: Date, zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.component(.weekday, from: instant)
    }

    static func isFriday(_ instant: Date, zone: TimeZone) -> Bool { weekday(instant, zone: zone) == 6 }

    /// Al-Kahf is read from Thursday's Maghrib to Friday's.
    static func isKahfTime(_ now: Date, today: DaySchedule?, zone: TimeZone) -> Bool {
        let day = weekday(now, zone: zone)
        guard let maghrib = today?[.maghrib] else { return day == 6 }
        return (day == 6 && now < maghrib) || (day == 5 && now >= maghrib)
    }

    /// "Jumu'ah Mubarak" on Friday, "Ramadan Kareem" in Ramadan, else nil.
    static func greetingKey(_ now: Date, zone: TimeZone, adjustment: Int) -> String? {
        if isFriday(now, zone: zone) { return "friday_mubarak" }
        if isRamadan(now, zone: zone, adjustment: adjustment) { return "ramadan_kareem" }
        return nil
    }

    /// What the next prayer means today, over its name: the iftar, the end of suhoor, go early to the Jumu'ah, or an
    /// hour of answered du'a before Friday's Maghrib. nil on an ordinary day.
    static func nextLabelKey(_ event: PrayerEvent, at: Date, now: Date, zone: TimeZone, adjustment: Int) -> String? {
        switch event {
        case .maghrib where isRamadan(at, zone: zone, adjustment: adjustment): return "ramadan_iftar"
        case .fajr where isRamadan(at, zone: zone, adjustment: adjustment): return "ramadan_suhoor_until"
        case .dhuhr where isFriday(at, zone: zone) && at.timeIntervalSince(now) < 3 * 3600: return "friday_early"
        case .maghrib where isFriday(now, zone: zone) && at.timeIntervalSince(now) < 3600: return "friday_answer_hour"
        default: return nil
        }
    }

    /// The fast's two times in Ramadan: today's iftar (Maghrib) and the end of the coming suhoor (the next Fajr).
    static func fast(_ now: Date, days: [DaySchedule], zone: TimeZone, adjustment: Int) -> (day: Int, iftar: Date, suhoorEnds: Date)? {
        guard days.count == 3, let h = hijri(now, zone: zone, adjustment: adjustment),
              let iftar = days[1][.maghrib], let fajr = days[1][.fajr] else { return nil }
        let nextFajr = now < fajr ? fajr : days[2][.fajr]
        let ramadanNow = h.month == 9
        let ramadanTomorrow = nextFajr.map { isRamadan($0, zone: zone, adjustment: adjustment) } ?? false
        guard ramadanNow || ramadanTomorrow, let suhoor = nextFajr else { return nil }
        return (ramadanNow ? h.day : 1, iftar, suhoor)
    }

    /// The next Adhan (Sunrise has none), where a recitation stops.
    static func nextAdhan(_ days: [DaySchedule], now: Date) -> Date? {
        days.lazy.flatMap { d in PrayerEvent.allCases.filter(\.isPrayer).compactMap { d[$0] } }.filter { $0 > now }.min()
    }
}
