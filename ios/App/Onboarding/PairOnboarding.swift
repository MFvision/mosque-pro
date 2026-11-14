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

    /// The answered questions in their order, with the side picked (the pile at the bottom, the chips when done).
    var answered: [(PairQuestion, Int)] { questions.compactMap { q in answers[q].map { (q, $0) } } }

    /// The tapped picture fills (a circle from the tap), flies into the pile, then the next pair comes (at once in
    /// still screenshots, sooner under Reduce Motion).
    private func moveOn() {
        advance?.cancel()
        let wait = still ? 0 : reduceMotion ? 450 : 860
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

