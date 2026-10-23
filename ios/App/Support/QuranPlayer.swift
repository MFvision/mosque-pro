import AVFoundation
import Foundation
import MediaPlayer
import NMCore
import Observation

/// Whole surahs and the Quran radio, streamed from mp3quran.net (free, no account); when a reciter's file won't load,
/// the same surah by Alafasy from QuranicAudio. One player for the app. It stops by itself at the next Adhan.
@MainActor
@Observable
final class QuranPlayer {
    static let shared = QuranPlayer()

    struct Reciter: Identifiable, Hashable {
        let id: String
        let base: String
        let ar: String
        let en: String
        func name(_ language: String) -> String { language == "ar" ? ar : en }
    }

    static let reciters: [Reciter] = [
        Reciter(id: "afs", base: "https://server8.mp3quran.net/afs/", ar: "مشاري العفاسي", en: "Mishary Alafasy"),
        Reciter(id: "maher", base: "https://server12.mp3quran.net/maher/", ar: "ماهر المعيقلي", en: "Maher Al-Muaiqly"),
        Reciter(id: "sds", base: "https://server11.mp3quran.net/sds/", ar: "عبدالرحمن السديس", en: "Abdulrahman Al-Sudais"),
        Reciter(id: "yasser", base: "https://server11.mp3quran.net/yasser/", ar: "ياسر الدوسري", en: "Yasser Al-Dosari"),
        Reciter(id: "s_gmd", base: "https://server7.mp3quran.net/s_gmd/", ar: "سعد الغامدي", en: "Saad Al-Ghamdi"),
        Reciter(id: "husr", base: "https://server13.mp3quran.net/husr/", ar: "محمود خليل الحصري", en: "Mahmoud Al-Husary"),
        Reciter(id: "basit", base: "https://server7.mp3quran.net/basit/", ar: "عبدالباسط عبدالصمد", en: "Abdul Basit"),
    ]
    static let fallbackBase = "https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/"
    static let radioURL = URL(string: "https://backup.qurango.net/radio/mix")!

    struct Surah: Hashable {
        let number: Int
        let ar: String
        let en: String
        func name(_ language: String) -> String { language == "ar" ? ar : en }
    }

    static let surahs: [Int: Surah] = Dictionary(uniqueKeysWithValues: [
        (1, "الفاتحة", "Al-Fatihah"), (2, "البقرة", "Al-Baqarah"), (12, "يوسف", "Yusuf"), (18, "الكهف", "Al-Kahf"),
        (19, "مريم", "Maryam"), (32, "السجدة", "As-Sajdah"), (36, "يس", "Ya-Sin"), (55, "الرحمن", "Ar-Rahman"),
        (56, "الواقعة", "Al-Waqi'ah"), (67, "الملك", "Al-Mulk"), (76, "الإنسان", "Al-Insan"), (78, "النبأ", "An-Naba'"),
        (87, "الأعلى", "Al-A'la"), (89, "الفجر", "Al-Fajr"), (93, "الضحى", "Ad-Duha"),
    ].map { ($0.0, Surah(number: $0.0, ar: $0.1, en: $0.2)) })
    /// The surahs offered by name (Al-Kahf leads on Friday).
    static let shown = [36, 55, 56, 67, 2, 12, 19, 1]
    /// "Play for me" picks from these on an ordinary day.
    static let lucky = [12, 18, 19, 32, 36, 55, 56, 67, 76, 78, 87, 89, 93]

    enum Item: Equatable {
        case surah(Int, reciter: String)
        case radio

        var surah: Int? { if case let .surah(n, _) = self { return n } else { return nil } }
    }

    /// Why "Play for me" chose its surah.
    enum Why { case friday, night, any }

    private(set) var playing: Item?
    /// The last start could not play (no internet, or both sources failed).
    private(set) var failed = false
    var reciterID: String {
        didSet { UserDefaults.standard.set(reciterID, forKey: "quranReciter") }
    }
    var reciter: Reciter { Self.reciters.first { $0.id == reciterID } ?? Self.reciters[0] }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var status: NSKeyValueObservation?
    @ObservationIgnored private var usedFallback = false
    @ObservationIgnored private var luckyPick: Int?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var until: Date?
    @ObservationIgnored private var language = "en"
    @ObservationIgnored private var radioTitle = "Quran"
    @ObservationIgnored private var remoteReady = false

    init() {
        reciterID = UserDefaults.standard.string(forKey: "quranReciter") ?? "afs"
    }

    /// Al-Kahf from Thursday's Maghrib to Friday's, Al-Mulk between Isha and Fajr (the Prophet ﷺ read it before sleep),
    /// else one of `lucky`, kept until it is played.
    func suggestion(now: Date, today: DaySchedule?, zone: TimeZone) -> (surah: Int, why: Why) {
        if Seasons.isKahfTime(now, today: today, zone: zone) { return (18, .friday) }
        if let t = today, let isha = t[.isha], let fajr = t[.fajr], now >= isha || now < fajr { return (67, .night) }
        if luckyPick == nil { luckyPick = Self.lucky.randomElement() }
        return (luckyPick ?? 36, .any)
    }

    /// Plays a surah in the chosen reciter's voice until it ends or `until` (the next Adhan).
    func play(surah n: Int, language: String, until: Date?) {
        self.language = language
        usedFallback = false
        luckyPick = nil
        start(.surah(n, reciter: reciter.id), url: Self.url(n, base: reciter.base), until: until)
    }

    func playRadio(title: String, language: String, until: Date?) {
        self.language = language
        radioTitle = title
        usedFallback = false
        start(.radio, url: Self.radioURL, until: until)
    }

    /// The new voice for what is playing, from the start of the surah.
    func setReciter(_ id: String, until: Date?) {
        reciterID = id
        if let n = playing?.surah { play(surah: n, language: language, until: until) }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
        player = nil
        status = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if playing != nil {
            playing = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            #if !os(macOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            #endif
        }
    }

    /// "Al-Kahf · Mishary Alafasy", or the radio's title.
    func title(_ language: String) -> String {
        switch playing {
        case let .surah(n, id)?:
            let who = Self.reciters.first { $0.id == id } ?? Self.reciters[0]
            return "\(Self.surahs[n]?.name(language) ?? "\(n)") · \(who.name(language))"
        case .radio?: return radioTitle
        case nil: return ""
        }
    }

    private static func url(_ n: Int, base: String) -> URL {
        URL(string: base + String(format: "%03d", n) + ".mp3")!
    }

    private func start(_ item: Item, url: URL, until: Date?) {
        stop()
        failed = false
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let p = AVPlayer(url: url)
        player = p
        playing = item
        status = p.currentItem?.observe(\.status) { [weak self] i, _ in
            guard i.status == .failed else { return }
            Task { @MainActor in self?.couldNotPlay() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
        observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.couldNotPlay() }
        })
        p.play()
        self.until = until
        if let until, until > Date() {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
        nowPlaying()
    }

    private func couldNotPlay() {
        if let n = playing?.surah, !usedFallback {
            usedFallback = true
            start(.surah(n, reciter: "afs"), url: Self.url(n, base: Self.fallbackBase), until: until)
            return
        }
        stop()
        failed = true
    }

    /// The title on the Lock Screen and in Control Center, with play, pause and stop.
    private func nowPlaying() {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title(language)]
        if playing == .radio { info[MPNowPlayingInfoPropertyIsLiveStream] = true }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard !remoteReady else { return }
        remoteReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let p = self?.player else { return }
                if p.timeControlStatus == .paused { p.play() } else { p.pause() }
            }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }
}
