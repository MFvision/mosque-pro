import Foundation
import Observation
#if os(iOS) && !targetEnvironment(macCatalyst)
import NetworkExtension
#endif

/// Clean network: ads and trackers blocked in every app on this iPhone or iPad, by name (ads.example.com and the
/// like), through AdGuard's free encrypted DNS and its ad and tracker list. The app hands iOS the DNS setting; the
/// person then picks it in Settings → General → VPN & Device Management → DNS (iOS asks for that step itself). No
/// traffic passes through the app. Ads served from the same address as the content (Instagram, TikTok, YouTube) stay.
@MainActor
@Observable
final class CleanNetwork {
    static let shared = CleanNetwork()

    enum State: Equatable {
        /// Not offered on this device (Mac, Apple Vision Pro).
        case unavailable
        case off
        /// Handed to iOS; waiting for the person to choose it in Settings.
        case needsSettings
        case on
    }

    private(set) var state: State = CleanNetwork.offered ? .off : .unavailable
    private(set) var busy = false
    /// Why iOS refused the setting, in the system's own words (shown under the switch), or nil.
    private(set) var problem: String?

    /// AdGuard DNS, the default servers (ads and trackers blocked).
    static let dohURL = URL(string: "https://dns.adguard-dns.com/dns-query")!
    static let servers = ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]

    var isOn: Bool { state == .on || state == .needsSettings }

    /// iPhone and iPad (the DNS setting isn't offered to this app on the Mac or Apple Vision Pro).
    static var offered: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Reads what iOS has (also after the person comes back from Settings).
    func refresh() async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let m = NEDNSSettingsManager.shared()
        do {
            try await m.loadFromPreferences()
            state = m.dnsSettings == nil ? .off : (m.isEnabled ? .on : .needsSettings)
        } catch {
            state = .off
            problem = error.localizedDescription
        }
        #endif
    }

    func set(_ on: Bool) async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        busy = true
        defer { busy = false }
        let m = NEDNSSettingsManager.shared()
        problem = nil
        do {
            try await m.loadFromPreferences()
            if on {
                let s = NEDNSOverHTTPSSettings(servers: Self.servers)
                s.serverURL = Self.dohURL
                m.dnsSettings = s
                m.localizedDescription = "Mosque Pro · AdGuard DNS"
                try await m.saveToPreferences()
            } else if m.dnsSettings != nil {
                try await m.removeFromPreferences()
            }
        } catch {
            // Refused or not allowed: say why, and drop what iOS didn't take so the state below is what is really set.
            problem = error.localizedDescription
            m.dnsSettings = nil
        }
        await refresh()
        #endif
    }
}
