import NMCore
import SwiftUI

/// Values for one instant, from the cached schedules (the countdown derives from instants).
struct TVSnapshot {
    let now: Date
    let today: DaySchedule?
    let next: Upcoming?
    let current: PrayerEvent?
    /// After an Adhan, the wait for its iqama (nil with the iqama off, or at any other time).
    let toIqama: PrayerMoment?
    let sky: SkyPeriod

    @MainActor
    init(_ model: TVModel, now: Date) {
        self.now = now
        let days = model.days(now: now)
        today = days.count == 3 ? days[1] : nil
        next = model.calculator.nextPrayer(days, now: now)
        let moment = model.calculator.moment(days, now: now, iqama: model.settings.iqama)
        toIqama = moment?.stage == .toIqama ? moment : nil
        if let t = today {
            current = PrayerEvent.allCases.last { (t[$0] ?? .distantFuture) <= now } ?? (days[0][.isha] != nil ? .isha : nil)
        } else {
            current = nil
        }
        sky = SkyPeriod.at(now, today: today, current: current)
    }
}

/// The prayer board: the sky of the hour, the city and both dates, the next prayer with a large
/// countdown, and today's six times along the bottom. Made to be left on screen in a home or a mosque.
struct BoardView: View {
    @Environment(TVModel.self) private var model
    @State private var player = QuranPlayer.shared
    @FocusState private var focused: Bool
    @State private var lastInput = Date()
    @State private var visible = false
    @State private var locked = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let snap = TVSnapshot(model, now: ctx.date)
            let sky = Sky.of(snap.sky)
            content(snap)
                .padding(.horizontal, 90)
                .padding(.vertical, 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { SkyBackdrop(sky: sky, horizon: 0.86).ignoresSafeArea() }
                .environment(\.sky, sky)
                .animation(.easeInOut(duration: 1.2), value: sky)
                .onChange(of: snap.now) { _, now in lockIfIdle(now) }
        }
        // Focus can rest on the board, so the tab bar slides away and the board fills the screen.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, _ in lastInput = Date() }
        .onAppear { visible = true; lastInput = Date() }
        .onDisappear { visible = false }
        .onChange(of: model.alert) { _, a in if a != nil { locked = false } }
        .fullScreenCover(isPresented: $locked, onDismiss: { lastInput = Date() }) {
            TVLockView { locked = false }
                .environment(model)
                .environment(\.locale, model.l10n.locale)
                .environment(\.layoutDirection, model.l10n.layoutDirection)
        }
    }

    /// Five minutes on the board without a press: the lock screen (not over the prayer alert).
    private func lockIfIdle(_ now: Date) {
        guard visible, !locked, model.settings.lockScreen, model.alert == nil, now.timeIntervalSince(lastInput) > 5 * 60 else { return }
        locked = true
    }

    @ViewBuilder
    private func content(_ snap: TVSnapshot) -> some View {
        let l10n = model.l10n
        let loc = model.settings.location
        let zone = loc?.zone ?? .current
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(loc?.name ?? "", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 44, weight: .semibold))
                    Text(Format.gregorian(CivilDate.of(snap.now, in: zone), locale: l10n.locale))
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(Format.hijri(CivilDate.of(snap.now, in: zone), adjustment: model.settings.prayer.hijriAdjustmentDays, locale: l10n.locale))
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.gold)
                    if let g = Seasons.greetingKey(snap.now, zone: zone, adjustment: model.settings.prayer.hijriAdjustmentDays) {
                        Label(l10n.t(g), systemImage: Seasons.isFriday(snap.now, zone: zone) ? "sparkles" : "moon.stars")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer()
                Text(Format.time(snap.now, zone: zone, locale: l10n.locale))
                    .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
            }

            Spacer(minLength: 20)

            if let wait = snap.toIqama, let iqama = wait.iqama {
                // From the Adhan to the iqama: the prayer being called and the time left to stand for it.
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("iqama_in"))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text(l10n.t(Format.prayerKey(wait.event)))
                            .font(.system(size: 110, weight: .bold))
                        Text(l10n.t("iqama_at", Format.time(iqama, zone: zone, locale: l10n.locale)))
                            .font(.system(size: 54, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.gold)
                    }
                    Text(Format.countdown(wait.until.timeIntervalSince(snap.now), locale: l10n.locale))
                        .font(.system(size: 150, weight: .thin, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(l10n.t("iqama_left", Format.remainingLong(wait.until.timeIntervalSince(snap.now), locale: l10n.locale)))
            } else if let next = snap.next {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t(Seasons.nextLabelKey(next.event, at: next.at, now: snap.now, zone: zone,
                                                     adjustment: model.settings.prayer.hijriAdjustmentDays) ?? "next_prayer"))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text(l10n.t(Format.prayerKey(next.event)))
                            .font(.system(size: 110, weight: .bold))
                        Text(Format.time(next.at, zone: zone, locale: l10n.locale))
                            .font(.system(size: 54, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.gold)
                    }
                    Text(Format.countdown(next.at.timeIntervalSince(snap.now), locale: l10n.locale))
                        .font(.system(size: 150, weight: .thin, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(l10n.t("countdown_a11y", l10n.t(Format.prayerKey(next.event)), Format.time(next.at, zone: zone, locale: l10n.locale),
                                           Format.remainingLong(next.at.timeIntervalSince(snap.now), locale: l10n.locale)))
            } else {
                Text(l10n.t("polar_unavailable_title")).font(.system(size: 54, weight: .semibold))
                Text(l10n.t("polar_unavailable_body")).font(.system(size: 30)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: 1200, alignment: .leading)
            }

            Spacer(minLength: 20)

            chips(snap, zone: zone)

            if let daily = Daily.content {
                DailyLine(content: daily, now: snap.now, zone: zone)
                Spacer(minLength: 20)
            }

            if let today = snap.today, today.status != .unavailable {
                HStack(spacing: 22) {
                    ForEach(PrayerEvent.allCases, id: \.self) { e in
                        PrayerTile(event: e, time: today[e].map { Format.time($0, zone: zone, locale: l10n.locale) } ?? "–",
                                   iqama: iqamaLine(e, today: today, zone: zone),
                                   isCurrent: e == snap.current && snap.today?[e] != nil, isNext: e == snap.next?.event && snap.next?.isTomorrow == false)
                    }
                }
                if today.status.isEstimated {
                    Text(l10n.t("estimated_badge")).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8)).padding(.top, 12)
                }
            }
        }
        .foregroundStyle(.white)
        // White text stays readable where the horizon glow is bright.
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }
}

extension BoardView {
    /// "Iqama 12:20" for a prayer's tile, with the iqama on.
    func iqamaLine(_ e: PrayerEvent, today: DaySchedule, zone: TimeZone) -> String? {
        let q = model.settings.iqama
        guard q.enabled, e.isPrayer, q.wait(e) > 0, let adhan = today[e] else { return nil }
        return model.l10n.t("iqama_at", Format.time(q.iqama(e, adhan: adhan), zone: zone, locale: model.l10n.locale))
    }

    /// Under the countdown: what is playing, the iftar or the end of suhoor in Ramadan (when the countdown isn't
    /// already counting to it), and Al-Kahf from Thursday's Maghrib to Friday's.
    @ViewBuilder func chips(_ snap: TVSnapshot, zone: TimeZone) -> some View {
        let l10n = model.l10n
        let adj = model.settings.prayer.hijriAdjustmentDays
        let fast = Seasons.fast(snap.now, days: model.days(now: snap.now), zone: zone, adjustment: adj)
        let kahf = Seasons.isKahfTime(snap.now, today: snap.today, zone: zone) && player.playing?.surah != 18
        let fastChip: (key: String, at: Date)? = fast.flatMap { f -> (key: String, at: Date)? in
            if let iftar = f.iftar, snap.now < iftar { return snap.next?.event == .maghrib ? nil : ("ramadan_iftar", iftar) }
            guard let suhoor = f.suhoorEnds else { return nil }
            return snap.next?.event == .fajr ? nil : ("ramadan_suhoor_until", suhoor)
        }
        if player.playing != nil || fastChip != nil || kahf {
            HStack(spacing: 20) {
                if player.playing != nil {
                    chip(icon: "waveform", title: l10n.t("quran_now_playing"), value: player.title(l10n.language), live: true)
                }
                if let fc = fastChip {
                    chip(icon: fc.key == "ramadan_iftar" ? "sunset" : "sun.horizon", title: l10n.t(fc.key),
                         value: Format.time(fc.at, zone: zone, locale: l10n.locale), live: false)
                }
                if kahf {
                    chip(icon: "book", title: l10n.t("friday_mubarak"), value: l10n.t("friday_kahf"), live: false)
                }
            }
            .padding(.top, 14)
        }
    }

    private func chip(icon: String, title: String, value: String, live: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.gold)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: live)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20)).foregroundStyle(.white.opacity(0.75))
                Text(value).font(.system(size: 28, weight: .semibold)).lineLimit(1)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// One of today's six times on glass; the prayer in progress is outlined in gold, the next one lit.
struct PrayerTile: View {
    @Environment(TVModel.self) private var model
    let event: PrayerEvent
    let time: String
    /// "Iqama 12:20", under the Adhan's time (nil for Sunrise, or with the iqama off).
    var iqama: String?
    let isCurrent: Bool
    let isNext: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 12) {
            Image(systemName: Theme.icon(event))
                .font(.system(size: 38))
                .foregroundStyle(isNext || isCurrent ? Theme.gold : .white.opacity(0.85))
            Text(model.l10n.t(Format.prayerKey(event)))
                .font(.system(size: 32, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(time)
                .font(.system(size: 40, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let iqama {
                Text(iqama)
                    .font(.system(size: 24).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .opacity(event.isPrayer ? 1 : 0.8)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .glass(shape, tint: isNext ? Theme.gold.opacity(0.28) : nil)
        .overlay(shape.stroke(Theme.gold, lineWidth: isCurrent ? 4 : 0))
        .accessibilityElement(children: .combine)
    }
}

/// Verse of the day and Hadith of the day on the board, taking turns every minute: the Arabic, then the
/// translation in the interface language and the reference.
struct DailyLine: View {
    @Environment(TVModel.self) private var model
    let content: DailyContent
    let now: Date
    let zone: TimeZone

    var body: some View {
        let l10n = model.l10n
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let showAyah = Int(now.timeIntervalSince1970 / 60) % 2 == 0
        let lines: (title: String, ar: String, translation: String?, note: String)
        if showAyah {
            let a = content.ayah(for: now, calendar: cal)
            lines = (l10n.t("daily_ayah"), a.ar, a.translation(l10n.language), Daily.reference(a, language: l10n.language, locale: l10n.locale))
        } else {
            let h = content.hadith(for: now, calendar: cal)
            let t = h.text(l10n.language)
            lines = (l10n.t("daily_hadith"), "«\(h.ar.text)»", l10n.language == "ar" ? nil : "«\(t.text)»", "\(t.grade) · \(t.source)")
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(lines.title).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gold)
            Text(lines.ar)
                .font(.system(size: 36))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let t = lines.translation {
                Text(t).font(.system(size: 26)).foregroundStyle(.white.opacity(0.85)).lineLimit(2).minimumScaleFactor(0.7)
            }
            Text(lines.note).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: 1500, alignment: .leading)
        .id(showAyah)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.8), value: showAyah)
        .accessibilityElement(children: .combine)
    }
}
