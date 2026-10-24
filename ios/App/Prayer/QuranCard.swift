import NMCore
import SwiftUI

/// The Quran on the Prayer screen: "Play for me" (Al-Kahf on Friday, Al-Mulk at night, else a surah picked for the
/// day), the Quran radio, a few surahs by name and the reciter. A tap plays; a tap on what is playing stops it. It
/// stops by itself at the next Adhan.
struct QuranCard: View {
    @Environment(\.appModel) private var model
    @Environment(\.l10n) private var l10n
    let snap: PrayerSnapshot
    @State private var player = QuranPlayer.shared

    var body: some View {
        let zone = snap.location?.zone ?? .current
        let pick = player.suggestion(now: snap.now, today: snap.today, zone: zone)
        let kahf = Seasons.isKahfTime(snap.now, today: snap.today, zone: zone)
        let lang = l10n.language
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(l10n.t("quran_title"), systemImage: "book")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    ForEach(QuranPlayer.reciters) { r in
                        Button {
                            player.setReciter(r.id, until: until)
                        } label: {
                            if r.id == player.reciterID { Label(r.name(lang), systemImage: "checkmark") } else { Text(r.name(lang)) }
                        }
                    }
                } label: {
                    Label(player.reciter.name(lang), systemImage: "person.wave.2")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityLabel(l10n.t("quran_reciter") + ", " + player.reciter.name(lang))
            }

            lead(pick: pick, lang: lang)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: l10n.t("quran_radio"), icon: "dot.radiowaves.left.and.right", on: player.playing == .radio) {
                        if player.playing == .radio { player.stop() } else { player.playRadio(title: l10n.t("quran_radio"), language: lang, until: until) }
                    }
                    ForEach((kahf ? [18] : []) + QuranPlayer.shown, id: \.self) { n in
                        let on = player.playing?.surah == n
                        chip(title: QuranPlayer.surahs[n]?.name(lang) ?? "\(n)", icon: nil, on: on) {
                            if on { player.stop() } else { player.play(surah: n, language: lang, until: until) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .sideScrollRow()

            if player.failed {
                Text(l10n.t("quran_play_error")).font(.footnote).foregroundStyle(Color(hex: 0xF2B8B5))
            }
        }
        .foregroundStyle(Theme.ink)
        .glassCard()
    }

    /// Where a recitation stops: the next Adhan.
    private var until: Date? { Seasons.nextAdhan(model.days(now: snap.now), now: snap.now) }

    /// What is playing with a Stop button, or the surah picked for now with a Play button.
    @ViewBuilder private func lead(pick: (surah: Int, why: QuranPlayer.Why), lang: String) -> some View {
        let playing = player.playing != nil
        let why: String = switch pick.why {
        case .friday: l10n.t("quran_why_friday")
        case .night: l10n.t("quran_why_night")
        case .any: l10n.t("quran_why_any")
        }
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playing ? l10n.t("quran_now_playing") : why)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(playing ? Theme.accent : Theme.ink.opacity(0.75))
                Text(playing ? player.title(lang) : (QuranPlayer.surahs[pick.surah]?.name(lang) ?? ""))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !playing {
                    Text(player.reciter.name(lang)).font(.footnote).foregroundStyle(Theme.ink.opacity(0.75))
                }
            }
            Spacer(minLength: 8)
            Button {
                if playing { player.stop() } else { player.play(surah: pick.surah, language: lang, until: until) }
            } label: {
                Label(playing ? l10n.t("stop") : l10n.t("quran_play_for_me"), systemImage: playing ? "stop.fill" : "play.fill")
                    .lineLimit(1)
            }
            .prominentButton()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gold.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.gold.opacity(0.45), lineWidth: 1))
    }

    private func chip(title: String, icon: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if on {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(on ? Theme.accent : Theme.ink)
            .background(Capsule().fill(on ? Theme.gold.opacity(0.18) : Theme.ink.opacity(0.08)))
            .overlay(Capsule().stroke(on ? Theme.gold.opacity(0.7) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Ramadan and Friday at the top of the Prayer screen: the greeting; in Ramadan the day of the month, the iftar and
/// the end of suhoor; on Friday, going early to the Jumu'ah and Surah Al-Kahf.
struct SeasonCard: View {
    @Environment(\.appModel) private var model
    @Environment(\.l10n) private var l10n
    let snap: PrayerSnapshot

    var body: some View {
        if let loc = snap.location {
            let zone = loc.zone
            let adj = model.settings.prayer.hijriAdjustmentDays
            let days = model.days(now: snap.now)
            let fast = Seasons.fast(snap.now, days: days, zone: zone, adjustment: adj)
            let friday = Seasons.isFriday(snap.now, zone: zone)
            let kahf = Seasons.isKahfTime(snap.now, today: snap.today, zone: zone)
            if fast != nil || friday || kahf {
                VStack(alignment: .leading, spacing: 10) {
                    if let g = Seasons.greetingKey(snap.now, zone: zone, adjustment: adj) ?? (kahf ? "friday_mubarak" : nil) {
                        Label(l10n.t(g), systemImage: friday || kahf ? "sparkles" : "moon.stars")
                            .font(.headline).foregroundStyle(Theme.accent)
                    }
                    if let fast {
                        Text(l10n.t("ramadan_day", fast.day)).font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            time(l10n.t("ramadan_iftar"), fast.iftar, zone, icon: "sunset")
                            time(l10n.t("ramadan_suhoor_until"), fast.suhoorEnds, zone, icon: "sun.horizon")
                        }
                    }
                    if let next = snap.next, next.event == .dhuhr, friday, next.at > snap.now, next.at.timeIntervalSince(snap.now) < 3 * 3600 {
                        Label(l10n.t("friday_early"), systemImage: "figure.walk").font(.subheadline)
                    }
                    if kahf {
                        Label(l10n.t("friday_kahf"), systemImage: "book").font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.ink)
                .glassCard(tint: Theme.gold.opacity(0.12))
            }
        }
    }

    private func time(_ title: String, _ at: Date, _ zone: TimeZone, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(Theme.ink.opacity(0.75))
            Text(Format.time(at, zone: zone, locale: l10n.locale)).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink.opacity(0.06)))
    }
}
