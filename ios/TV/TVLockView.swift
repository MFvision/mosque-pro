import AVFoundation
import NMCore
import SwiftUI
import UIKit

/// The lock screen: the tawaf around the Kaaba, live and slowly drifting, with the time large over it, both dates, the
/// next prayer counting down, the verse of the day and what is playing. After Maghrib the film is dimmer and warmer.
/// Any press brings the board back.
struct TVLockView: View {
    @Environment(TVModel.self) private var model
    var onWake: () -> Void
    @State private var player = QuranPlayer.shared
    @State private var drift = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let snap = TVSnapshot(model, now: ctx.date)
            ZStack {
                film(evening: evening(snap))
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .environment(\.layoutDirection, .leftToRight)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                content(snap)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .focusable()
        .focusEffectDisabled()
        .onTapGesture(perform: onWake)
        .onMoveCommand { _ in onWake() }
        .onPlayPauseCommand(perform: onWake)
    }

    private func evening(_ snap: TVSnapshot) -> Bool {
        guard let t = snap.today, let maghrib = t[.maghrib], let fajr = t[.fajr] else { return false }
        return snap.now >= maghrib || snap.now < fajr
    }

    @ViewBuilder private func film(evening: Bool) -> some View {
        if let url = Bundle.main.url(forResource: "kaaba-tawaf", withExtension: "mp4") {
            LoopingVideo(url: url)
                .scaleEffect(drift ? 1.14 : 1.04)
                .offset(x: drift ? -20 : 0, y: drift ? 12 : 0)
                .animation(.easeInOut(duration: 60).repeatForever(autoreverses: true), value: drift)
                .onAppear { drift = true }
                .brightness(evening ? -0.18 : -0.06)
                .saturation(evening ? 0.85 : 1)
                .overlay(evening ? Color(hex: 0x3A2208).opacity(0.18) : .clear)
        } else {
            SkyBackdrop(sky: Sky.of(.isha), horizon: 0.9)
        }
    }

    @ViewBuilder private func content(_ snap: TVSnapshot) -> some View {
        let l10n = model.l10n
        let loc = model.settings.location
        let zone = loc?.zone ?? .current
        let adj = model.settings.prayer.hijriAdjustmentDays
        let day = CivilDate.of(snap.now, in: zone)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let g = Seasons.greetingKey(snap.now, zone: zone, adjustment: adj) {
                    Text(l10n.t(g)).font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.gold)
                    Text(loc?.name ?? "").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Label(loc?.name ?? "", systemImage: "mappin.and.ellipse").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.gold)
                }
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 60) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Format.time(snap.now, zone: zone, locale: l10n.locale))
                        .font(.system(size: 220, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
                    (Text(Format.gregorian(day, locale: l10n.locale)) + Text("  ·  ") +
                     Text(Format.hijri(day, adjustment: adj, locale: l10n.locale)).foregroundColor(Theme.gold))
                        .font(.system(size: 32)).foregroundStyle(.white.opacity(0.85))
                    if let next = snap.next {
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(l10n.t(Seasons.nextLabelKey(next.event, at: next.at, now: snap.now, zone: zone, adjustment: adj) ?? "next_prayer"))
                                .font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                            Text(l10n.t(Format.prayerKey(next.event))).font(.system(size: 40, weight: .bold))
                            Text(Format.countdown(next.at.timeIntervalSince(snap.now), locale: l10n.locale))
                                .font(.system(size: 38, weight: .light).monospacedDigit()).foregroundStyle(Theme.gold)
                        }
                        .padding(.horizontal, 30).padding(.vertical, 16)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().stroke(Theme.gold.opacity(0.5), lineWidth: 1.5))
                        .padding(.top, 10)
                    }
                    if player.playing != nil {
                        Label(player.title(l10n.language), systemImage: "waveform")
                            .font(.system(size: 28)).foregroundStyle(Color(hex: 0x7FD1BF))
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }
                Spacer(minLength: 0)
                if let daily = Daily.content {
                    ayah(daily, now: snap.now, zone: zone)
                }
            }
        }
        .padding(.horizontal, 100)
        .padding(.vertical, 70)
    }

    private func ayah(_ content: DailyContent, now: Date, zone: TimeZone) -> some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let a = content.ayah(for: now, calendar: cal)
        return VStack(alignment: .trailing, spacing: 12) {
            Text(a.ar)
                .font(.system(size: 34))
                .multilineTextAlignment(.trailing)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .environment(\.layoutDirection, .rightToLeft)
                .shadow(color: .black.opacity(0.6), radius: 10)
            Text(Daily.reference(a, language: model.l10n.language, locale: model.l10n.locale))
                .font(.system(size: 22)).foregroundStyle(Theme.gold)
        }
        .frame(maxWidth: 640, alignment: .trailing)
    }
}

/// A silent film that loops, filling its frame.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.play(url)
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {}

    static func dismantleUIView(_ v: PlayerView, coordinator: ()) { v.stop() }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var looper: AVPlayerLooper?
        private var queue: AVQueuePlayer?

        func play(_ url: URL) {
            let q = AVQueuePlayer()
            q.isMuted = true
            looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
            let l = layer as! AVPlayerLayer
            l.player = q
            l.videoGravity = .resizeAspectFill
            q.play()
            queue = q
        }

        func stop() {
            queue?.pause()
            looper = nil
            queue = nil
        }
    }
}
