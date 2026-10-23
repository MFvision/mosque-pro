import NMCore
import SwiftUI

/// The Quran on Apple TV: "Play for me" (Al-Kahf on Friday, Al-Mulk at night, else a surah picked for the day), the
/// Quran radio, the reciter, and surahs by name. Select plays; select on what is playing stops it. A recitation stops
/// by itself at the next Adhan.
struct TVQuranView: View {
    @Environment(TVModel.self) private var model
    @State private var player = QuranPlayer.shared
    @State private var choosingReciter = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        let l10n = model.l10n
        let lang = l10n.language
        let now = Date()
        let zone = model.settings.location?.zone ?? .current
        let days = model.days(now: now)
        let today = days.count == 3 ? days[1] : nil
        let pick = player.suggestion(now: now, today: today, zone: zone)
        let kahf = Seasons.isKahfTime(now, today: today, zone: zone)
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text(l10n.t("quran_title")).font(.system(size: 56, weight: .bold))
                HStack(spacing: 40) {
                    lead(pick: pick, lang: lang)
                    Button {
                        if player.playing == .radio { player.stop() } else { player.playRadio(title: l10n.t("quran_radio"), language: lang, until: until) }
                    } label: {
                        tile(icon: player.playing == .radio ? "waveform" : "dot.radiowaves.left.and.right", title: l10n.t("quran_radio"),
                             detail: l10n.t("quran_radio_live"), on: player.playing == .radio)
                    }
                    .buttonStyle(.card)
                    Button { choosingReciter = true } label: {
                        tile(icon: "person.wave.2", title: player.reciter.name(lang), detail: l10n.t("quran_reciter"), on: false)
                    }
                    .buttonStyle(.card)
                }
                if player.failed {
                    Text(l10n.t("quran_play_error")).font(.system(size: 28)).foregroundStyle(Color(hex: 0xF2B8B5))
                }
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach((kahf ? [18] : []) + QuranPlayer.shown, id: \.self) { n in
                        let on = player.playing?.surah == n
                        Button {
                            if on { player.stop() } else { player.play(surah: n, language: lang, until: until) }
                        } label: {
                            surahTile(n, on: on, lang: lang)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 40)
        }
        .foregroundStyle(.white)
        .background { SkyBackdrop(sky: Sky.of(.isha), horizon: 0.9).ignoresSafeArea() }
        .confirmationDialog(l10n.t("quran_reciter"), isPresented: $choosingReciter) {
            ForEach(QuranPlayer.reciters) { r in
                Button(r.name(lang)) { player.setReciter(r.id, until: until) }
            }
        }
    }

    private var until: Date? {
        Seasons.nextAdhan(model.days(now: Date()), now: Date())
    }

    @ViewBuilder private func lead(pick: (surah: Int, why: QuranPlayer.Why), lang: String) -> some View {
        let l10n = model.l10n
        let playing = player.playing != nil
        let why: String = switch pick.why {
        case .friday: l10n.t("quran_why_friday")
        case .night: l10n.t("quran_why_night")
        case .any: l10n.t("quran_why_any")
        }
        Button {
            if playing { player.stop() } else { player.play(surah: pick.surah, language: lang, until: until) }
        } label: {
            HStack(spacing: 30) {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 8) {
                    Text(playing ? l10n.t("quran_now_playing") : why)
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gold)
                    Text(playing ? player.title(lang) : (QuranPlayer.surahs[pick.surah]?.name(lang) ?? ""))
                        .font(.system(size: 46, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                    Text(playing ? l10n.t("stop") : l10n.t("quran_play_for_me") + " · " + player.reciter.name(lang))
                        .font(.system(size: 26)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(36)
            .frame(width: 860, height: 260, alignment: .leading)
            .background(LinearGradient(colors: [Theme.gold.opacity(0.35), Theme.gold.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .buttonStyle(.card)
    }

    private func tile(icon: String, title: String, detail: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 50)).foregroundStyle(Theme.gold)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: on)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 32, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 22)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .padding(28)
        .frame(width: 380, height: 260, alignment: .leading)
        .background(on ? Theme.gold.opacity(0.22) : Color.white.opacity(0.06))
    }

    private func surahTile(_ n: Int, on: Bool, lang: String) -> some View {
        let s = QuranPlayer.surahs[n]
        return VStack(spacing: 10) {
            Text(n.formatted(.number.locale(model.l10n.locale))).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.gold)
            Text(s?.ar ?? "").font(.system(size: 54)).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                if on { Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating) }
                Text(lang == "ar" ? " " : (s?.en ?? "")).font(.system(size: 22)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(on ? Theme.gold.opacity(0.22) : Color.white.opacity(0.06))
    }
}
