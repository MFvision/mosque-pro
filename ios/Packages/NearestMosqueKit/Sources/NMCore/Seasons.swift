import Foundation

/// Ramadan and Friday on the prayer screens: the greeting, what the next prayer means that day (the iftar, the end
/// of suhoor, going early to the Jumu'ah, the last hour of Friday) and when Surah Al-Kahf is read. Months are Umm
/// al-Qura's with the user's Hijri adjustment, as the dates shown elsewhere.
public enum Seasons {
    public static func hijri(_ instant: Date, zone: TimeZone, adjustment: Int) -> HijriCalendar.HijriDate? {
        HijriCalendar.of(CivilDate.of(instant, in: zone), adjustmentDays: adjustment)
    }

    public static func isRamadan(_ instant: Date, zone: TimeZone, adjustment: Int) -> Bool {
        hijri(instant, zone: zone, adjustment: adjustment)?.month == 9
    }

    /// 1 is Sunday, 5 Thursday, 6 Friday.
    public static func weekday(_ instant: Date, zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.component(.weekday, from: instant)
    }

    public static func isFriday(_ instant: Date, zone: TimeZone) -> Bool { weekday(instant, zone: zone) == 6 }

    /// Al-Kahf is read from Thursday's Maghrib to Friday's.
    public static func isKahfTime(_ now: Date, today: DaySchedule?, zone: TimeZone) -> Bool {
        let day = weekday(now, zone: zone)
        guard let maghrib = today?[.maghrib] else { return day == 6 }
        return (day == 6 && now < maghrib) || (day == 5 && now >= maghrib)
    }

    /// "Jumu'ah Mubarak" on Friday, "Ramadan Kareem" in Ramadan, else nil.
    public static func greetingKey(_ now: Date, zone: TimeZone, adjustment: Int) -> String? {
        if isFriday(now, zone: zone) { return "friday_mubarak" }
        if isRamadan(now, zone: zone, adjustment: adjustment) { return "ramadan_kareem" }
        return nil
    }

    /// What the next prayer means today, over its name: the iftar, the end of suhoor, go early to the Jumu'ah, or an
    /// hour of answered du'a before Friday's Maghrib. nil on an ordinary day.
    public static func nextLabelKey(_ event: PrayerEvent, at: Date, now: Date, zone: TimeZone, adjustment: Int) -> String? {
        switch event {
        case .maghrib where isRamadan(at, zone: zone, adjustment: adjustment): return "ramadan_iftar"
        case .fajr where isRamadan(at, zone: zone, adjustment: adjustment): return "ramadan_suhoor_until"
        case .dhuhr where isFriday(at, zone: zone) && at.timeIntervalSince(now) < 3 * 3600: return "friday_early"
        case .maghrib where isFriday(now, zone: zone) && at.timeIntervalSince(now) < 3600: return "friday_answer_hour"
        default: return nil
        }
    }

    /// The fast's times in Ramadan: today's iftar (Maghrib), only while today is in Ramadan, and the end of the coming
    /// suhoor (the next Fajr), only while that Fajr is still in Ramadan, so never on the night before Eid (fasting
    /// on Eid is forbidden) and never an iftar on the night before Ramadan. `days` is yesterday, today and tomorrow.
    public struct Fast: Equatable, Sendable {
        /// The day of Ramadan (1 on the night before it begins).
        public let day: Int
        public let iftar: Date?
        public let suhoorEnds: Date?
    }

    public static func fast(_ now: Date, days: [DaySchedule], zone: TimeZone, adjustment: Int) -> Fast? {
        guard days.count == 3, let h = hijri(now, zone: zone, adjustment: adjustment),
              let fajr = days[1][.fajr] else { return nil }
        let nextFajr = now < fajr ? fajr : days[2][.fajr]
        let ramadanNow = h.month == 9
        let suhoor = nextFajr.flatMap { isRamadan($0, zone: zone, adjustment: adjustment) ? $0 : nil }
        let iftar = ramadanNow ? days[1][.maghrib] : nil
        guard iftar != nil || suhoor != nil else { return nil }
        return Fast(day: ramadanNow ? h.day : 1, iftar: iftar, suhoorEnds: suhoor)
    }

    /// The next Adhan (Sunrise has none), where a recitation stops.
    public static func nextAdhan(_ days: [DaySchedule], now: Date) -> Date? {
        days.lazy.flatMap { d in PrayerEvent.allCases.filter(\.isPrayer).compactMap { d[$0] } }.filter { $0 > now }.min()
    }
}
