import NMCore
import SwiftUI
import UserNotifications

// "One or two": the welcome flow as a row of two-picture questions under one line that never changes ("Which one
// feels like you? Don't overthink it."), like an eye test. Tap a picture and it is saved through the real setting at
// once, then the next pair slides in. Welcome, the pairs, the one permission (notifications), a short "building" beat,
// done. Replaces First Light (OnboardingView) as the first-run flow; Settings → Show welcome tour opens this too.

/// One question, asked as two pictures. The raw value is its name for `-demoOnboardingStep` (the place keeps "where").
enum PairQuestion: String, CaseIterable, Identifiable {
    case place = "where", asr, voice, alarm, appearance, style, styleFinal = "style2", friday, clean
    var id: String { rawValue }
}

enum PairPage: Equatable {
    case welcome, question(PairQuestion), notify, building, done
}

@MainActor
@Observable
final class PairOnboardingModel {
    let app: AppModel
    /// The questions this device asks: the alarm only where AlarmKit is, Clean network only on iPhone and iPad.
    let questions: [PairQuestion]
    private(set) var page: PairPage = .welcome
    /// Which side was tapped on this page (0 or 1), held while it moves on.
    private(set) var picked: Int?
    /// Each answered question and its side (the pile at the bottom).
    private(set) var answers: [PairQuestion: Int] = [:]
    /// Going on (true) or back: the direction the pages slide.
    private(set) var forward = true
    private(set) var notificationsDenied = false
    /// The first style round's pick, which meets a new one in the second round.
    private(set) var styleWinner: WidgetLook
    var locating = false
    var locateError: String?
    var citySheet = false
    var reduceMotion = false
    let still: Bool
    @ObservationIgnored private var advance: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        var q = PairQuestion.allCases
        if PrayerAlarms.permission == .unavailable { q.removeAll { $0 == .alarm } }
        if !CleanNetwork.offered { q.removeAll { $0 == .clean } }
        questions = q
        styleWinner = WidgetLook(rawValue: app.settings.widgetLook) ?? .cream
        var still = false
        #if DEBUG
        // Screenshots: `-demoOnboardingStep asr` (welcome, where, asr, voice, alarm, appearance, style, style2, friday,
        // clean, notify, done) and `-demoOnboardingStill YES` (no timers or motion).
        let d = UserDefaults.standard
        still = d.bool(forKey: "demoOnboardingStill")
        if let key = d.string(forKey: "demoOnboardingStep"), let p = Self.page(key, in: q) { page = p }
        #endif
        self.still = still
    }

    static func page(_ key: String, in questions: [PairQuestion]) -> PairPage? {
        switch key {
        case "promise", "welcome": return .welcome
        case "notify", "privacy": return .notify
        case "done": return .done
        default: return PairQuestion(rawValue: key).flatMap { questions.contains($0) ? .question($0) : nil }
        }
    }

    var question: PairQuestion? {
        if case .question(let q) = page { return q }
        return nil
    }

    var index: Int? { question.flatMap { questions.firstIndex(of: $0) } }

    /// How far through the questions (0 on the first, 1 from the permission on).
    var progress: Double {
        switch page {
        case .welcome: return 0
        case .question: return Double(index ?? 0) / Double(max(1, questions.count))
        case .notify, .building, .done: return 1
        }
    }

    private var motion: Animation { reduceMotion || still ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86) }

    // MARK: Moving

    func go(_ p: PairPage, forward f: Bool = true) {
        advance?.cancel()
        if !AdhanPlayer.shared.isAdhan { AdhanPlayer.shared.stop() }
        locateError = nil
        forward = f
        withAnimation(motion) {
            picked = nil
            page = p
        }
        switch p {
        case .notify: Task { await checkNotifications() }
        case .building: build()
        default: break
        }
    }

    func begin() { if let first = questions.first { go(.question(first)) } }

    func next() {
        guard let i = index else { return }
        go(i + 1 < questions.count ? .question(questions[i + 1]) : .notify)
    }

    func back() {
        switch page {
        case .question:
            guard let i = index else { return }
            go(i > 0 ? .question(questions[i - 1]) : .welcome, forward: false)
        case .notify:
            if let last = questions.last { go(.question(last), forward: false) }
        default: break
        }
    }

    /// Skip keeps the setting as it is. Not on the place while none is set: the times need one.
    var canSkip: Bool { question != nil && !(question == .place && app.settings.location == nil) }

    func skip() {
        if question == .style { styleWinner = WidgetLook(rawValue: app.settings.widgetLook) ?? styleWinner }
        next()
    }

    /// A short pause on the tapped picture, then the next pair (none in still screenshots).
    private func moveOn() {
        advance?.cancel()
        let wait = still ? 0 : 650
        advance = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(wait))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    // MARK: Answers

    func pick(_ side: Int) {
        guard let q = question, picked == nil, !locating else { return }
        if q == .place {
            pickPlace(side)
            return
        }
        withAnimation(motion) {
            picked = side
            answers[q] = side
        }
        apply(q, side)
        if q == .clean, side == 1 {
            // iOS may ask to add the DNS setting first; move on once it has answered.
            Task {
                await CleanNetwork.shared.set(true)
                moveOn()
            }
        } else {
            moveOn()
        }
    }

    private func apply(_ q: PairQuestion, _ side: Int) {
        var a = app.settings.alerts
        switch q {
        case .place: break
        case .asr: app.setMadhab(side == 0 ? .SHAFI : .HANAFI)
        case .voice: app.setAlerts(a.with(side == 0 ? .makkah : .madinah), askPermission: false)
        case .alarm:
            a.adhanAlarm = side == 1
            app.setAlerts(a, askPermission: false)
        case .appearance: UserDefaults.standard.set(side == 0 ? "light" : "dark", forKey: "appearance")
        case .style, .styleFinal:
            let look = styles(q)[side]
            app.settings.widgetLook = look.rawValue
            if q == .style { styleWinner = look }
        case .friday:
            a.friday = side == 0
            app.setAlerts(a, askPermission: false)
        case .clean: break
        }
    }

    /// The two styles of a round: Gold and cream or Night garden, then the pick or Desert lantern.
    func styles(_ q: PairQuestion) -> [WidgetLook] {
        if q == .style { return [.cream, .nightGarden] }
        let other: WidgetLook = styleWinner == .desertLantern ? .charcoalCrimson : .desertLantern
        return [styleWinner, other]
    }

    // MARK: Place

    private func pickPlace(_ side: Int) {
        guard side == 0 else {
            citySheet = true
            return
        }
        locating = true
        Task {
            let before = app.settings.location
            let outcome = await app.useDeviceLocation()
            locating = false
            switch outcome {
            case .ok: if app.settings.location == before { placeSet(0) }
            case .denied: locateError = app.l10n.t("location_denied")
            case .noFix: locateError = app.l10n.t("location_fix_failed")
            }
        }
    }

    /// A place came in (the fix, or a city from the picker): mark that side and move on.
    func placeSet(_ side: Int? = nil) {
        guard question == .place, picked == nil else { return }
        let s = side ?? (locating || app.settings.location?.source == .device ? 0 : 1)
        withAnimation(motion) {
            picked = s
            answers[.place] = s
        }
        moveOn()
    }

    // MARK: Notifications

    private func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }

    /// The only permission the flow asks for. The prayer bells go on either way (they ring once allowed in Settings).
    func allow() {
        Task {
            if !notificationsDenied {
                _ = await Reminders.requestAuthorization()
                if app.wantsAlarms { await PrayerAlarms.requestAuthorization() }
            }
            await app.enablePrayerBells()
            go(.building)
        }
    }

    func notNow() { go(.building) }

    /// A short "building your prayer day" beat, so the end never looks like nothing happened.
    private func build() {
        advance = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(self?.still == true ? 0 : 1100))
            guard !Task.isCancelled else { return }
            self?.go(.done)
        }
    }

    func stop() {
        advance?.cancel()
        if !AdhanPlayer.shared.isAdhan { AdhanPlayer.shared.stop() }
    }
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
                .transition(pageTransition)
        }
        .environment(\.onb, onb)
        .foregroundStyle(.white)
        // The flow is drawn on its own night sky in every appearance; the light or dark pick applies to the app.
        .preferredColorScheme(.dark)
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

    private var pageTransition: AnyTransition {
        if reduceMotion || model.still { return .opacity }
        let lead: Edge = l10n.isRTL ? .leading : .trailing
        let trail: Edge = l10n.isRTL ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: model.forward ? lead : trail).combined(with: .opacity),
                           removal: .move(edge: model.forward ? trail : lead).combined(with: .opacity))
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .welcome: welcome
        case .question(let q): PairQuestionPage(model: model, question: q)
        case .notify: notify
        case .building: building
        case .done: done
        }
    }

    // MARK: Single pages

    private var welcome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LanguageMenu()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
            HeroDisc(moon: false, halo: true)
                .padding(.bottom, 28)
                .accessibilityHidden(true)
            Text(l10n.t("onb2_promise_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(l10n.t(OnbContext.isPhone ? "onb2_promise_body" : "onb2_promise_body_device"))
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Spacer()
            PairPrimaryButton(title: l10n.t("onb2_begin")) { model.begin() }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private var notify: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.gold)
                .padding(.bottom, 24)
                .accessibilityHidden(true)
            Text(l10n.t("onb2_notify"))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(model.notificationsDenied ? l10n.t("notifications_denied")
                 : l10n.t(OnbContext.isPhone ? "onb2_ask_confirm" : "onb2_ask_confirm_device"))
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Spacer()
            PairPrimaryButton(title: l10n.t(model.notificationsDenied ? "onb2_continue" : "onb2_allow")) { model.allow() }
            if !model.notificationsDenied {
                Button(l10n.t("not_now")) { model.notNow() }
                    .buttonStyle(.plain)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(minHeight: 44)
                    .padding(.top, 8)
            }
            Button(l10n.t("onb_back")) { model.back() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var building: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.gold).controlSize(.large)
            Text(l10n.t("onb2_building"))
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var done: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroDisc(moon: false, halo: true)
                .padding(.bottom, 28)
                .accessibilityHidden(true)
            Text(l10n.t("onb2_done_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if let line = nextLine {
                Text(line)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            if CleanNetwork.shared.state == .needsSettings {
                Text(l10n.t("clean_network_step"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
            Spacer()
            PairPrimaryButton(title: l10n.t("onb2_open_app")) { finish() }
            Text(l10n.t("onb2_change_later"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    /// "Asr at 3:21 PM in Riyadh."
    private var nextLine: String? {
        let now = Date()
        guard let loc = app.settings.location, let next = app.calculator.nextPrayer(app.days(now: now), now: now) else { return nil }
        return l10n.t("onb2_done_sub", l10n.t(Format.prayerKey(next.event)), Format.time(next.at, zone: loc.zone, locale: l10n.locale), loc.name)
    }

    private func finish() {
        model.stop()
        app.settings.onboarded = true
        dismiss()
    }
}

// MARK: - A question

/// The fixed line, the topic, the two pictures, and at the bottom the pile of answers, the progress and Back and Skip.
struct PairQuestionPage: View {
    let model: PairOnboardingModel
    let question: PairQuestion
    @Environment(\.appModel) private var app
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(l10n.t("onb3_ask"))
                    .font(.title2.bold())
                Text(l10n.t("onb3_ask_sub"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(topic)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 14) {
                option(0)
                option(1)
            }
            .padding(.horizontal, 18)
            if let error = model.locateError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xF2B8B5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 12)
            footer
        }
    }

    private var topic: String {
        switch question {
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

    private func title(_ side: Int) -> String {
        switch question {
        case .place: return l10n.t(side == 0 ? "use_my_location" : "search_city")
        case .asr: return l10n.t(side == 0 ? "onb2_asr_standard" : "asr_hanafi")
        case .voice: return l10n.t(side == 0 ? "onb2_chip_makkah" : "onb2_chip_madinah")
        case .alarm: return l10n.t(side == 0 ? "check_kind_notification" : "check_kind_alarm")
        case .appearance: return l10n.t(side == 0 ? "appearance_light" : "appearance_dark")
        case .style, .styleFinal: return l10n.t("style_" + model.styles(question)[side].rawValue)
        case .friday: return l10n.t(side == 0 ? "alerts_friday" : "alerts_off")
        case .clean: return l10n.t(side == 0 ? "not_now" : "clean_network")
        }
    }

    /// The line under a title: today's Asr time for each school.
    private func detail(_ side: Int) -> String? {
        guard question == .asr, let loc = app.settings.location else { return nil }
        let times = app.calculator.asrTimes(loc.location, date: CivilDate.of(Date(), in: loc.zone), zone: loc.zone, settings: app.settings.prayer)
        guard let at = times[side == 0 ? .SHAFI : .HANAFI] else { return nil }
        return l10n.t("onb2_asr_at", Format.time(at, zone: loc.zone, locale: l10n.locale))
    }

    /// The side tapped on this page.
    private func current(_ side: Int) -> Bool {
        if let p = model.picked { return p == side }
        return false
    }

    private func recording(_ side: Int) -> String? {
        guard question == .voice else { return nil }
        return AudioCatalog.adhan(source: side == 0 ? .makkah : .madinah, fajr: false)
    }

    private func option(_ side: Int) -> some View {
        let on = current(side)
        let dim = model.picked != nil && !on
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let name = title(side)
        return VStack(spacing: 10) {
            Button { model.pick(side) } label: {
                PairArt(question: question, side: side, look: question == .style || question == .styleFinal ? model.styles(question)[side] : nil)
                    .aspectRatio(140 / 220, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(on ? Theme.gold : .white.opacity(0.18), lineWidth: on ? 3 : 1.5) }
                    .overlay {
                        if question == .place, side == 0, model.locating {
                            ProgressView().tint(.white).controlSize(.large)
                        }
                    }
                    .scaleEffect(on ? 1.03 : 1)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(name)
            .accessibilityValue(detail(side) ?? "")
            .accessibilityAddTraits(on ? .isSelected : [])
            Text(numberText(side))
                .font(.subheadline.bold())
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(on ? Theme.gold : .white.opacity(0.14), in: Circle())
                .foregroundStyle(on ? Theme.navyNight : .white)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = detail(side) {
                    Text(d)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.gold)
                }
            }
            .accessibilityHidden(true)
            if let rec = recording(side) {
                let playing = AdhanPlayer.shared.playing == rec
                Button { AdhanPlayer.shared.toggle(rec) } label: {
                    Label(l10n.t(playing ? "alarm_stop" : "preview_play", name), systemImage: playing ? "stop.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(playing ? Theme.gold.opacity(0.3) : .white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(dim ? 0.35 : 1)
        .frame(maxWidth: .infinity)
    }

    private func numberText(_ side: Int) -> String {
        Format.number(Double(side + 1), digits: 0, locale: l10n.locale)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(Array(model.answers.keys.sorted { $0.rawValue < $1.rawValue }.prefix(8)), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.gold.opacity(0.35))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1.2))
                            .frame(width: 16, height: 22)
                    }
                    if model.answers.isEmpty {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1.2)
                            .frame(width: 16, height: 22)
                    }
                }
                .accessibilityHidden(true)
                Text(l10n.t("onb3_learning"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(Theme.gold).frame(width: geo.size.width * model.progress)
                }
            }
            .frame(height: 4)
            .environment(\.layoutDirection, l10n.layoutDirection)
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
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .buttonStyle(.plain)
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
                .foregroundStyle(Theme.navyNight)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color(hex: 0xD4A843), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

/// The night sky behind the flow: navy at the top to the deepest navy below.
struct PairBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x24618A), Theme.navyDeep, Theme.navyNight], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0xD4A843).opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
    }
}

/// The picture for one side of a question, drawn in 140 × 220 points and scaled to fit. Never mirrored.
struct PairArt: View {
    let question: PairQuestion
    let side: Int
    var look: WidgetLook?

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 140, geo.size.height / 220)
            drawing
                .frame(width: 140, height: 220)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: 140 * k, height: 220 * k, alignment: .topLeading)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private static let navy = Color(hex: 0x16405C)
    private static let gold = Color(hex: 0xD4A843)
    private static let ink = Color(hex: 0x10202B)

    @ViewBuilder private var drawing: some View {
        switch question {
        case .place: side == 0 ? AnyView(near) : AnyView(city)
        case .asr: AnyView(asr)
        case .voice: side == 0 ? AnyView(makkah) : AnyView(madinah)
        case .alarm: side == 0 ? AnyView(banner) : AnyView(alarm)
        case .appearance: AnyView(home(dark: side == 1))
        case .style, .styleFinal: AnyView(style(look ?? .cream))
        case .friday: side == 0 ? AnyView(friday) : AnyView(quietFriday)
        case .clean: side == 0 ? AnyView(ads) : AnyView(clean)
        }
    }

    private func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color, r: CGFloat = 3) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(c).frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }

    private var near: some View {
        ZStack(alignment: .topLeading) {
            Self.navy
            Path { p in
                for y in [60, 120, 170] as [CGFloat] { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: 140, y: y)) }
                for x in [40, 95] as [CGFloat] { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 220)) }
            }
            .stroke(Color(hex: 0x2F6A8F), lineWidth: 1)
            Path { p in p.move(to: CGPoint(x: 0, y: 20)); p.addLine(to: CGPoint(x: 140, y: 200)) }
                .stroke(Color(hex: 0x245475), lineWidth: 6)
            Circle().fill(Self.gold.opacity(0.18)).frame(width: 68, height: 68).position(x: 70, y: 110)
            Circle().fill(Self.gold).overlay(Circle().strokeBorder(.white, lineWidth: 3)).frame(width: 20, height: 20).position(x: 70, y: 110)
        }
    }

    private var city: some View {
        ZStack(alignment: .topLeading) {
            Self.navy
            Capsule().fill(.white.opacity(0.9)).frame(width: 112, height: 26).position(x: 70, y: 39)
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.navy).position(x: 30, y: 39)
            bar(14, 72, 80, 8, .white.opacity(0.85), r: 4)
            bar(14, 102, 64, 8, .white.opacity(0.85), r: 4)
            bar(14, 132, 90, 8, .white.opacity(0.85), r: 4)
            bar(14, 162, 70, 8, .white.opacity(0.85), r: 4)
        }
    }

    private var asr: some View {
        ZStack {
            Color(hex: 0x14354D)
            AsrShadowArt(hanafi: side == 1)
                .frame(width: 128, height: 82)
                .position(x: 70, y: 120)
            Text(side == 0 ? "×1" : "×2")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Self.gold)
                .position(x: 70, y: 190)
        }
    }

    private func waves(play: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array([16, 28, 16, 36, 20].enumerated()), id: \.offset) { i, h in
                bar(22 + CGFloat(i) * 8, 178 - CGFloat(h) / 2, 4, CGFloat(h), Self.gold, r: 2)
            }
            Circle().fill(Self.gold).frame(width: 28, height: 28).position(x: 104, y: 178)
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.navyDeep).position(x: 104, y: 178)
        }
    }

    private var makkah: some View {
        ZStack(alignment: .topLeading) {
            Theme.navyDeep
            Circle().fill(Self.gold.opacity(0.12)).frame(width: 80, height: 80).position(x: 70, y: 70)
            Rectangle().fill(Color(hex: 0x111111)).frame(width: 44, height: 44).position(x: 70, y: 118)
            Rectangle().fill(Self.gold).frame(width: 44, height: 5).position(x: 70, y: 108)
            waves(play: false)
        }
    }

    private var madinah: some View {
        ZStack(alignment: .topLeading) {
            Theme.navyDeep
            Circle().fill(Color(hex: 0x5FAE7D).opacity(0.14)).frame(width: 80, height: 80).position(x: 70, y: 70)
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).fill(Color(hex: 0x3F8F5C)).frame(width: 44, height: 50).position(x: 70, y: 115)
            Rectangle().fill(Self.gold).frame(width: 4, height: 12).position(x: 70, y: 86)
            Rectangle().fill(Color(hex: 0xCFD8DE)).frame(width: 6, height: 48).position(x: 33, y: 116)
            Rectangle().fill(Color(hex: 0xCFD8DE)).frame(width: 6, height: 48).position(x: 107, y: 116)
            waves(play: false)
        }
    }

    private func clock(_ y: CGFloat, size: CGFloat) -> some View {
        Text("3:12").font(.system(size: size, weight: .light, design: .rounded)).foregroundStyle(.white).position(x: 70, y: y)
    }

    private var banner: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x24384A)
            clock(60, size: 32)
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.88)).frame(width: 116, height: 38).position(x: 70, y: 107)
            bar(20, 96, 14, 14, Self.gold, r: 4)
            bar(40, 97, 60, 6, Self.ink)
            bar(40, 108, 76, 5, Color(hex: 0x4A5A66))
        }
    }

    private var alarm: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x0B1620)
            clock(66, size: 36)
            Image(systemName: "alarm").font(.system(size: 20)).foregroundStyle(Self.gold).position(x: 70, y: 106)
            Capsule().fill(Self.gold).frame(width: 96, height: 30).position(x: 70, y: 147)
            Capsule().fill(.white.opacity(0.14)).frame(width: 96, height: 30).position(x: 70, y: 187)
        }
    }

    private func home(dark: Bool) -> some View {
        let bg = dark ? Color(hex: 0x0B1620) : Color(hex: 0xF2F2F7)
        let card = dark ? Color(hex: 0x14232F) : .white
        let text = dark ? Color(hex: 0xF1F4F6) : Self.ink
        let sub = dark ? Color(hex: 0xA9B6C0) : Color(hex: 0x4A5A66)
        let accent = dark ? Self.gold : Color(hex: 0x8A6A1C)
        return ZStack(alignment: .topLeading) {
            bg
            bar(12, 20, 116, 60, card, r: 14)
            bar(22, 32, 40, 6, accent)
            bar(22, 46, 70, 12, text, r: 4)
            ForEach(0..<4, id: \.self) { i in
                bar(12, 92 + CGFloat(i) * 28, 116, 22, card, r: 8)
                bar(20, 100 + CGFloat(i) * 28, CGFloat([34, 30, 36, 28][i]), 6, sub)
            }
        }
    }

    private func style(_ look: WidgetLook) -> some View {
        let palette = WidgetPalette.of(look, period: .maghrib)
        let accent = StyleAccent.dark(look.rawValue)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(palette.background)
            bar(12, 20, 116, 74, .white.opacity(0.14), r: 16)
            bar(22, 32, 36, 6, accent)
            bar(22, 46, 76, 14, .white.opacity(0.92), r: 4)
            bar(22, 68, 50, 6, .white.opacity(0.5))
            bar(12, 104, 54, 54, .white.opacity(0.14), r: 14)
            bar(74, 104, 54, 54, .white.opacity(0.14), r: 14)
            Circle().fill(accent).frame(width: 20, height: 20).position(x: 39, y: 131)
            Circle().strokeBorder(accent, lineWidth: 3).frame(width: 20, height: 20).position(x: 101, y: 131)
            bar(12, 168, 116, 34, accent, r: 12)
        }
    }

    private var friday: some View {
        ZStack(alignment: .topLeading) {
            Theme.navy
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.9)).frame(width: 116, height: 40).position(x: 70, y: 60)
            bar(20, 49, 14, 14, Self.gold, r: 4)
            bar(40, 50, 54, 6, Self.ink)
            bar(40, 61, 74, 5, Color(hex: 0x4A5A66))
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x3F8F5C)).frame(width: 48, height: 62).position(x: 70, y: 141)
            RoundedRectangle(cornerRadius: 2).strokeBorder(Self.gold, lineWidth: 2).frame(width: 36, height: 46).position(x: 70, y: 141)
        }
    }

    private var quietFriday: some View {
        ZStack(alignment: .topLeading) {
            Theme.navy
            Text("12:05").font(.system(size: 30, weight: .light, design: .rounded)).foregroundStyle(.white).position(x: 70, y: 96)
            Image(systemName: "bell.slash").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6)).position(x: 70, y: 130)
        }
    }

    private var ads: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            bar(10, 14, 120, 40, Color(hex: 0xFF5A5A), r: 6)
            Text("AD").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).position(x: 70, y: 34)
            bar(10, 66, 110, 6, Color(hex: 0xC9D1D7))
            bar(10, 78, 90, 6, Color(hex: 0xC9D1D7))
            bar(10, 94, 120, 50, Color(hex: 0xFFB84D), r: 6)
            Text("AD").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).position(x: 70, y: 119)
            bar(10, 156, 100, 6, Color(hex: 0xC9D1D7))
            bar(10, 168, 80, 6, Color(hex: 0xC9D1D7))
            bar(10, 184, 120, 26, Color(hex: 0x7A5CFF), r: 6)
        }
    }

    private var clean: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            bar(10, 20, 110, 6, Color(hex: 0xC9D1D7))
            bar(10, 32, 90, 6, Color(hex: 0xC9D1D7))
            bar(10, 44, 100, 6, Color(hex: 0xC9D1D7))
            bar(10, 66, 120, 60, Color(hex: 0xE8EEF2), r: 8)
            bar(10, 140, 110, 6, Color(hex: 0xC9D1D7))
            bar(10, 152, 80, 6, Color(hex: 0xC9D1D7))
            Circle().fill(Theme.navy).frame(width: 36, height: 36).position(x: 108, y: 186)
            Image(systemName: "checkmark.shield.fill").font(.system(size: 16)).foregroundStyle(Self.gold).position(x: 108, y: 186)
        }
    }
}
