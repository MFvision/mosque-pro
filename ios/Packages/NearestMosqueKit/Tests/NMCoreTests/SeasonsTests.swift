import XCTest
@testable import NMCore

/// The Ramadan times on the Prayer screen and the Apple TV board: never a suhoor on the night before Eid, never an
/// iftar on the night before Ramadan.
final class SeasonsTests: XCTestCase {
    private let calc = PrayerCalculator()
    private let makkah = LatLng(21.4225, 39.8262)!
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    private func days(around d: CivilDate) -> [DaySchedule] {
        (-1...1).map { calc.schedule(makkah, date: d.adding(days: $0), zone: zone, settings: PrayerSettings(method: .UMM_AL_QURA)) }
    }

    /// The first civil date in 2026 whose Umm al-Qura month is `month` and whose next day's is `next`.
    private func edge(_ month: Int, then next: Int) throws -> CivilDate {
        var d = CivilDate(year: 2026, month: 1, day: 1)
        for _ in 0..<366 {
            if HijriCalendar.of(d, adjustmentDays: 0)?.month == month, HijriCalendar.of(d.adding(days: 1), adjustmentDays: 0)?.month == next {
                return d
            }
            d = d.adding(days: 1)
        }
        throw XCTSkip("no month \(month) → \(next) edge in 2026")
    }

    func testNightBeforeEidHasNoSuhoor() throws {
        let last = try edge(9, then: 10)
        let ds = days(around: last)
        let night = ds[1][.maghrib]!.addingTimeInterval(3600)
        let fast = try XCTUnwrap(Seasons.fast(night, days: ds, zone: zone, adjustment: 0))
        XCTAssertNil(fast.suhoorEnds, "a suhoor on the night before Eid")
        XCTAssertEqual(fast.iftar, ds[1][.maghrib])
        XCTAssertGreaterThanOrEqual(fast.day, 29)
        // The Fajr of Eid is labelled as an ordinary Fajr.
        XCTAssertNil(Seasons.nextLabelKey(.fajr, at: ds[2][.fajr]!, now: night, zone: zone, adjustment: 0))
    }

    func testLastDayBeforeFajrStillHasSuhoor() throws {
        let last = try edge(9, then: 10)
        let ds = days(around: last)
        let early = ds[1][.fajr]!.addingTimeInterval(-3600)
        let fast = try XCTUnwrap(Seasons.fast(early, days: ds, zone: zone, adjustment: 0))
        XCTAssertEqual(fast.suhoorEnds, ds[1][.fajr])
        XCTAssertEqual(fast.iftar, ds[1][.maghrib])
    }

    func testMiddleOfRamadanHasBoth() throws {
        let first = try edge(8, then: 9).adding(days: 1)
        let mid = first.adding(days: 10)
        let ds = days(around: mid)
        let night = ds[1][.maghrib]!.addingTimeInterval(3600)
        let fast = try XCTUnwrap(Seasons.fast(night, days: ds, zone: zone, adjustment: 0))
        XCTAssertEqual(fast.day, 11)
        XCTAssertEqual(fast.iftar, ds[1][.maghrib])
        XCTAssertEqual(fast.suhoorEnds, ds[2][.fajr])
    }

    func testNightBeforeRamadanHasSuhoorButNoIftar() throws {
        let eve = try edge(8, then: 9)
        let ds = days(around: eve)
        let night = ds[1][.maghrib]!.addingTimeInterval(3600)
        let fast = try XCTUnwrap(Seasons.fast(night, days: ds, zone: zone, adjustment: 0))
        XCTAssertNil(fast.iftar, "an iftar on the night before Ramadan")
        XCTAssertEqual(fast.suhoorEnds, ds[2][.fajr])
        XCTAssertEqual(fast.day, 1)
    }

    func testOrdinaryDayHasNothing() {
        let ds = days(around: CivilDate(year: 2026, month: 10, day: 15))
        XCTAssertNil(Seasons.fast(ds[1][.dhuhr]!, days: ds, zone: zone, adjustment: 0))
    }

    func testKahfFromThursdayMaghribToFriday() {
        // 2026-10-15 is a Thursday.
        let thu = days(around: CivilDate(year: 2026, month: 10, day: 15))[1]
        XCTAssertFalse(Seasons.isKahfTime(thu[.maghrib]!.addingTimeInterval(-60), today: thu, zone: zone))
        XCTAssertTrue(Seasons.isKahfTime(thu[.maghrib]!.addingTimeInterval(60), today: thu, zone: zone))
        let fri = days(around: CivilDate(year: 2026, month: 10, day: 16))[1]
        XCTAssertTrue(Seasons.isKahfTime(fri[.dhuhr]!, today: fri, zone: zone))
        XCTAssertFalse(Seasons.isKahfTime(fri[.maghrib]!.addingTimeInterval(60), today: fri, zone: zone))
    }
}
