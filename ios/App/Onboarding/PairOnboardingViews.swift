import NMCore
import SwiftUI

// The look of "one or two": a white base with a faint eight-point star lattice, frosted glass cards, navy ink, and gold
// only on what is chosen. Motion: the pair slides in one card after the other, the tapped card fills with a circle from
// the tap and flies into the pile at the bottom, the title and the last screen rise in. Reduce Motion: short fades.

enum PairInk {
    static let base = Color(hex: 0xF6F7F8)
    static let ink = Color(hex: 0x10202B)
    static let ink2 = Color(hex: 0x5B6B77)
    static let hair = Color(hex: 0x10202B).opacity(0.09)
    static let gold = Color(hex: 0xC9A042)
    static let tile = Color(hex: 0xEEF2F5)
    static let line = Color(hex: 0xE3E9EE)
    static let muted = Color(hex: 0xB9C5CE)
    static let green = Color(hex: 0x3E8E5E)
    /// Strong ease-out and ease-in-out (for movement on screen).
    static let out = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.52)
    static let move = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.44)
}

// MARK: - The flow

struct PairOnboardingView: View {
    @Environment(\.appModel) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = PairOnboardingModel(app: AppModel.shared)

    var body: some View {
        let onb = OnbContext(wide: false, phone: OnbContext.isPhone, still: model.still)
        ZStack {
            PairBackground().ignoresSafeArea()
            content
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .id(pageKey)
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
        .environment(\.onb, onb)
        .foregroundStyle(PairInk.ink)
        // The flow keeps its own light look; the light or dark pick applies to the app behind it.
        .preferredColorScheme(.light)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onAppear { model.reduceMotion = reduceMotion }
        .onDisappear { model.stop() }
        .onChange(of: reduceMotion) { _, r in model.reduceMotion = r }
        .onChange(of: app.settings.location) { old, new in if new != nil, new != old { model.placeSet() } }
        .sensoryFeedback(.selection, trigger: model.picked) { _, new in new != nil }
        .sheet(isPresented: $model.citySheet) {
            CityPickerView()
                .environment(\.locale, l10n.locale)
                .environment(\.layoutDirection, l10n.layoutDirection)
        }
    }

    private var pageKey: String {
        switch model.page {
        case .welcome: return "welcome"
        case .question(let q): return q.rawValue
        case .notify: return "notify"
        case .building: return "building"
        case .done: return "done"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .welcome: PairWelcome(model: model)
        case .question(let q): PairQuestionPage(model: model, question: q)
        case .notify: PairNotify(model: model)
        case .building:
            VStack(spacing: 16) {
                ProgressView().tint(PairInk.ink).controlSize(.large)
                Text(l10n.t("onb2_building")).font(.headline).foregroundStyle(PairInk.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done: PairDone(model: model) { finish() }
        }
    }

    private func finish() {
        model.stop()
        app.settings.onboarded = true
        dismiss()
    }
}

// MARK: - Entering motion

/// Rises in from below, sharpening from a blur, after `delay` (shown at once in still screenshots).
struct PairRise: ViewModifier {
    let delay: Double
    var distance: CGFloat = 16
    var blur: CGFloat = 8
    @Environment(\.onb) private var onb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let on = shown || onb.still
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : distance)
            .scaleEffect(on || reduceMotion ? 1 : 0.97)
            .blur(radius: on || reduceMotion ? 0 : blur)
            .onAppear {
                guard !shown, !onb.still else { return }
                withAnimation((reduceMotion ? .easeOut(duration: 0.25) : PairInk.out).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

extension View {
    func pairRise(_ delay: Double, distance: CGFloat = 16, blur: CGFloat = 8) -> some View {
        modifier(PairRise(delay: delay, distance: distance, blur: blur))
    }

    /// Frosted glass on the white base: material, a white edge, a hairline and a soft shadow.
    func pairGlass<S: InsettableShape>(_ shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
            .background(Color.white.opacity(0.55), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .overlay(shape.inset(by: -0.5).stroke(PairInk.hair, lineWidth: 1))
            .shadow(color: PairInk.ink.opacity(0.14), radius: 16, x: 0, y: 12)
    }
}

// MARK: - Welcome, permission, done

struct PairWelcome: View {
    let model: PairOnboardingModel
    @Environment(\.l10n) private var l10n
    @Environment(\.onb) private var onb
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LanguageMenu()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
            PairMark()
                .frame(width: 96, height: 96)
                .pairGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .mask(Circle().scale(revealed || onb.still ? 1.6 : 0.01))
                .scaleEffect(revealed || onb.still ? 1 : 0.9)
                .onAppear { withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.7)) { revealed = true } }
                .accessibilityHidden(true)
            Text(l10n.t("app_name"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PairInk.ink2)
                .padding(.top, 14)
                .pairRise(0.3, distance: 6, blur: 4)
            Text(l10n.t("onb2_promise_title"))
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 26)
                .pairRise(0.42, distance: 18)
            Text(l10n.t(onb.phone ? "onb2_promise_body" : "onb2_promise_body_device"))
                .font(.body)
                .foregroundStyle(PairInk.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .pairRise(0.6, distance: 10, blur: 4)
            Spacer()
            PairPrimaryButton(title: l10n.t("onb2_begin")) { model.begin() }
                .pairRise(0.72, distance: 10, blur: 4)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
}

/// The app's mark on the welcome: a gold crescent under a small finial.
struct PairMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 58
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + (x - 29) * s, y: c.y + (y - 29) * s) }
            var moon = Path(ellipseIn: CGRect(origin: p(9, 9), size: CGSize(width: 40 * s, height: 40 * s)))
            moon = moon.subtracting(Path(ellipseIn: CGRect(origin: p(19, 7), size: CGSize(width: 34 * s, height: 34 * s))))
            ctx.fill(moon, with: .color(PairInk.gold))
            var fin = Path()
            fin.move(to: p(29, 3)); fin.addLine(to: p(33, 12)); fin.addLine(to: p(29, 9)); fin.addLine(to: p(25, 12)); fin.closeSubpath()
            ctx.fill(fin, with: .color(PairInk.ink))
        }
        .padding(18)
    }
}

struct PairNotify: View {
    let model: PairOnboardingModel
    @Environment(\.l10n) private var l10n
    @Environment(\.onb) private var onb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 36, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(PairInk.gold, PairInk.ink)
                .symbolEffect(.wiggle, options: .repeating, isActive: !reduceMotion && !onb.still)
                .frame(width: 88, height: 88)
                .pairGlass(Circle())
                .padding(.bottom, 22)
                .pairRise(0)
                .accessibilityHidden(true)
            Text(l10n.t("onb2_notify"))
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .pairRise(0.07)
            Text(model.notificationsDenied ? l10n.t("notifications_denied")
                 : l10n.t(onb.phone ? "onb2_ask_confirm" : "onb2_ask_confirm_device"))
                .font(.body)
                .foregroundStyle(PairInk.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .pairRise(0.14)
            Spacer()
            VStack(spacing: 4) {
                PairPrimaryButton(title: l10n.t(model.notificationsDenied ? "onb2_continue" : "onb2_allow")) { model.allow() }
                if !model.notificationsDenied {
                    Button(l10n.t("not_now")) { model.notNow() }
                        .buttonStyle(.plain)
                        .font(.body)
                        .foregroundStyle(PairInk.ink2)
                        .frame(minHeight: 44)
                }
                Button(l10n.t("onb_back")) { model.back() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(PairInk.ink2.opacity(0.8))
                    .frame(minHeight: 44)
            }
            .pairRise(0.21, distance: 10, blur: 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

struct PairDone: View {
    let model: PairOnboardingModel
    let onOpen: () -> Void
    @Environment(\.appModel) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.onb) private var onb
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(l10n.t("onb2_done_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .pairRise(0, distance: 18)
            if let next {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("next_prayer") + " · " + next.city)
                            .font(.caption)
                            .foregroundStyle(PairInk.ink2)
                        Text(next.name).font(.title2.bold())
                    }
                    Spacer()
                    Text(next.time).font(.title2.bold()).monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .pairGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .mask(Circle().scale(revealed || onb.still ? 3 : 0.01))
                .padding(.top, 22)
                .onAppear { withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.65).delay(0.2)) { revealed = true } }
            }
            PairFlow(spacing: 6) {
                ForEach(Array(model.answered.enumerated()), id: \.offset) { i, item in
                    Text(PairText.name(item.0, item.1, model: model, l10n: l10n))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .pairGlass(Capsule())
                        .pairRise(0.5 + Double(i) * 0.055, distance: 10, blur: 4)
                }
            }
            .padding(.top, 16)
            if CleanNetwork.shared.state == .needsSettings {
                Text(l10n.t("clean_network_step"))
                    .font(.footnote)
                    .foregroundStyle(PairInk.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
            Spacer()
            PairPrimaryButton(title: l10n.t("onb2_open_app"), action: onOpen)
                .pairRise(0.7, distance: 10, blur: 4)
            Text(l10n.t("onb2_change_later"))
                .font(.footnote)
                .foregroundStyle(PairInk.ink2)
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var next: (name: String, time: String, city: String)? {
        let now = Date()
        guard let loc = app.settings.location, let n = app.calculator.nextPrayer(app.days(now: now), now: now) else { return nil }
        return (l10n.t(Format.prayerKey(n.event)), Format.time(n.at, zone: loc.zone, locale: l10n.locale), loc.name)
    }
}

/// Lays its children in rows, centred, wrapping to the next row when one is full.
struct PairFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var out: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let w = cur.items.isEmpty ? s.width : cur.width + spacing + s.width
            if w > width, !cur.items.isEmpty {
                out.append(cur)
                cur = ([i], s.width, s.height)
            } else {
                cur = (cur.items + [i], w, max(cur.height, s.height))
            }
        }
        if !cur.items.isEmpty { out.append(cur) }
        return out
    }
}

// MARK: - A question

enum PairText {
    static func topic(_ q: PairQuestion, l10n: Localization) -> String {
        switch q {
        case .place: return l10n.t("onb2_where_title")
        case .asr: return l10n.t("asr_method")
        case .voice: return l10n.t("adhan_section")
        case .alarm: return l10n.t("adhan_alarm_toggle")
        case .appearance: return l10n.t("appearance")
        case .style, .styleFinal: return l10n.t("app_style_title")
        case .friday: return l10n.t("onb2_friday_title")
        case .clean: return l10n.t("clean_network")
        }
    }

    @MainActor static func name(_ q: PairQuestion, _ side: Int, model: PairOnboardingModel, l10n: Localization) -> String {
        switch q {
        case .place: return l10n.t(side == 0 ? "use_my_location" : "search_city")
        case .asr: return l10n.t(side == 0 ? "onb2_asr_standard" : "asr_hanafi")
        case .voice: return l10n.t(side == 0 ? "onb2_chip_makkah" : "onb2_chip_madinah")
        case .alarm: return l10n.t(side == 0 ? "check_kind_notification" : "check_kind_alarm")
        case .appearance: return l10n.t(side == 0 ? "appearance_light" : "appearance_dark")
        case .style, .styleFinal: return l10n.t("style_" + model.styles(q)[side].rawValue)
        case .friday: return l10n.t(side == 0 ? "alerts_friday" : "alerts_off")
        case .clean: return l10n.t(side == 0 ? "not_now" : "clean_network")
        }
    }
}

/// The fixed line, the topic, the two pictures, and at the bottom the pile of answers, the progress and Back and Skip.
struct PairQuestionPage: View {
    let model: PairOnboardingModel
    let question: PairQuestion
    @Environment(\.appModel) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.onb) private var onb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the tap landed in each card (0…1), the fill's progress and the flight to the pile.
    @State private var tap = UnitPoint.center
    @State private var fill = false
    @State private var flying = false
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var pileFrame: CGRect = .zero

    private static let space = "pairs"

    var body: some View {
        VStack(spacing: 0) {
            // The line that never changes.
            VStack(spacing: 6) {
                Text(l10n.t("onb3_ask")).font(.title2.bold())
                Text(l10n.t("onb3_ask_sub")).font(.subheadline).foregroundStyle(PairInk.ink2)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Circle().fill(PairInk.gold).frame(width: 6, height: 6)
                Text(PairText.topic(question, l10n: l10n)).font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .pairGlass(Capsule())
            .padding(.top, 20)
            .pairRise(0, distance: 0, blur: 6)
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 12) {
                option(0).pairRise(0.06, distance: 26, blur: 10)
                option(1).pairRise(0.15, distance: 26, blur: 10)
            }
            .padding(.horizontal, 16)
            if let error = model.locateError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xB3261E))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 12)
            footer
        }
        .coordinateSpace(.named(Self.space))
        .onChange(of: model.picked) { _, p in if p != nil { pickedMotion() } }
    }

    private func pickedMotion() {
        if reduceMotion || onb.still {
            fill = true
            return
        }
        withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.46)) { fill = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(PairInk.move) { flying = true }
        }
    }

    // MARK: Options

    private func detail(_ side: Int) -> String? {
        guard question == .asr, let loc = app.settings.location else { return nil }
        let times = app.calculator.asrTimes(loc.location, date: CivilDate.of(Date(), in: loc.zone), zone: loc.zone, settings: app.settings.prayer)
        guard let at = times[side == 0 ? .SHAFI : .HANAFI] else { return nil }
        return l10n.t("onb2_asr_at", Format.time(at, zone: loc.zone, locale: l10n.locale))
    }

    private func recording(_ side: Int) -> String? {
        guard question == .voice else { return nil }
        return AudioCatalog.adhan(source: side == 0 ? .makkah : .madinah, fajr: false)
    }

    private func flight(_ side: Int) -> CGSize {
        guard flying, model.picked == side, let c = cardFrames[side], pileFrame != .zero else { return .zero }
        let target = CGPoint(x: l10n.isRTL ? pileFrame.minX : pileFrame.maxX, y: pileFrame.midY)
        return CGSize(width: target.x - c.midX, height: target.y - c.midY)
    }

    private func option(_ side: Int) -> some View {
        let on = model.picked == side
        let dim = model.picked != nil && !on
        let outer = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let name = PairText.name(question, side, model: model, l10n: l10n)
        let playing = recording(side).map { AdhanPlayer.shared.playing == $0 } ?? false
        return VStack(spacing: 10) {
            ZStack {
                PairArt(question: question, side: side, look: lookFor(side), playing: playing, rtl: l10n.isRTL)
                    .clipShape(inner)
                // The fill: a circle from the tap point, with a gold check.
                ZStack {
                    PairInk.ink.opacity(0.58)
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(PairInk.gold, in: Circle())
                }
                .clipShape(inner)
                .mask {
                    GeometryReader { g in
                        let d = max(g.size.width, g.size.height) * 2.6
                        Circle()
                            .frame(width: d, height: d)
                            .scaleEffect(on && fill ? 1 : 0.001)
                            .position(x: g.size.width * tap.x, y: g.size.height * tap.y)
                    }
                }
                .allowsHitTesting(false)
                if question == .place, side == 0, model.locating {
                    ProgressView().tint(PairInk.ink).controlSize(.large)
                }
            }
            .aspectRatio(7 / 10, contentMode: .fit)
            .padding(7)
            .pairGlass(outer)
            .contentShape(outer)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { cardFrames[side] = $0 }
            .onTapGesture(coordinateSpace: .local) { p in
                if let f = cardFrames[side], f.width > 0 { tap = UnitPoint(x: p.x / f.width, y: p.y / f.height) }
                model.pick(side)
            }
            .offset(flight(side))
            .scaleEffect(flying && on ? 0.12 : 1)
            .opacity(flying && on ? 0.2 : 1)
            .zIndex(on ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(detail(side) ?? "")
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.pick(side) }
            HStack(spacing: 8) {
                Text(Format.number(Double(side + 1), digits: 0, locale: l10n.locale))
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(on ? PairInk.gold : .white, in: Circle())
                    .overlay(Circle().strokeBorder(on ? PairInk.gold : PairInk.hair, lineWidth: 1))
                    .foregroundStyle(on ? .white : PairInk.ink)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(flying && on ? 0 : 1)
            .accessibilityHidden(true)
            if let d = detail(side) {
                Text(d)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(PairInk.ink2)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
            }
            if let rec = recording(side) {
                Button { AdhanPlayer.shared.toggle(rec) } label: {
                    Label(playing ? l10n.t("alarm_stop") : l10n.t("preview_play", name), systemImage: playing ? "stop.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.navy)
                        .frame(width: 44, height: 36)
                        .pairGlass(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(dim ? 0.25 : 1)
        .scaleEffect(dim && !reduceMotion ? 0.94 : 1)
        .blur(radius: dim && !reduceMotion ? 2 : 0)
        .animation(.easeOut(duration: 0.26), value: dim)
        .frame(maxWidth: .infinity)
    }

    private func lookFor(_ side: Int) -> WidgetLook? {
        question == .style || question == .styleFinal ? model.styles(question)[side] : nil
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: -10) {
                    let items = model.answered.suffix(7)
                    if items.isEmpty {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(PairInk.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 20, height: 28)
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        PairArt(question: item.0, side: item.1, look: item.0 == .style || item.0 == .styleFinal ? model.styles(item.0)[item.1] : nil,
                                playing: false, rtl: l10n.isRTL, animated: false)
                            .frame(width: 20, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
                            .shadow(color: PairInk.ink.opacity(0.25), radius: 3, y: 2)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { pileFrame = $0 }
                .accessibilityHidden(true)
                Text(l10n.t("onb3_learning"))
                    .font(.footnote)
                    .foregroundStyle(PairInk.ink2)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PairInk.ink.opacity(0.08))
                    Capsule().fill(PairInk.ink).frame(width: geo.size.width * model.progress)
                }
            }
            .frame(height: 3)
            .accessibilityElement()
            .accessibilityLabel(l10n.t("onb_page_a11y", (model.index ?? 0) + 1, model.questions.count))
            HStack {
                Button(l10n.t("onb_back")) { model.back() }
                    .frame(minHeight: 44)
                Spacer()
                if model.canSkip {
                    Button(l10n.t("onb_skip")) { model.skip() }
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(PairInk.ink2)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}

// MARK: - Pieces

struct PairPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(PairInk.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PairPress())
        .hoverEffect(.highlight)
    }
}

/// Pressed: 97% for 160 ms, so the button feels heard.
struct PairPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// The white base and its faint eight-point star lattice (the glass has something to frost).
struct PairBackground: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PairInk.base))
            let step: CGFloat = 56
            var star = Path()
            var y: CGFloat = 0
            while y < size.height + step {
                var x: CGFloat = 0
                while x < size.width + step {
                    let c = CGPoint(x: x + 28, y: y + 28)
                    var p = Path()
                    for i in 0..<8 {
                        let a = Double(i) * .pi / 4 - .pi / 2
                        let r: CGFloat = i % 2 == 0 ? 22 : 9.2
                        let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    star.addPath(p)
                    let square = CGRect(x: c.x - 7.8, y: c.y - 7.8, width: 15.6, height: 15.6)
                    star.addPath(Path(square).applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: .pi / 4).translatedBy(x: -c.x, y: -c.y)))
                    x += step
                }
                y += step
            }
            ctx.stroke(star, with: .color(PairInk.ink.opacity(0.05)), lineWidth: 1)
        }
    }
}
