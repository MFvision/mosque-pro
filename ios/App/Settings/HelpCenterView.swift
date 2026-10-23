import NMCore
import SwiftUI
import UIKit

/// The Help Center's answers and how to reach us, from shared/help/help.json (nil if the file is missing).
enum Help {
    static let center: HelpCenter? = Bundle.main.url(forResource: "help", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? HelpCenter.load($0) }

    /// What the person sent, newest first, kept on this device only.
    static let historyKey = "helpRequests"
}

/// Settings → Help Center: answers to common problems (searchable in Arabic and English), Report a problem, Suggest
/// an idea, Ask us a question, and what the person has already sent with its reference. There is no server yet: messages
/// go by email, and we reply there.
struct HelpCenterView: View {
    @Environment(\.l10n) private var l10n
    @State private var query = ""
    @State private var open: String?
    @AppStorage(Help.historyKey) private var historyData = Data()

    var body: some View {
        let results = Help.center?.search(query, platform: .phone) ?? []
        let history = SupportRequest.decodeList(historyData)
        Form {
            Section {
                if results.isEmpty {
                    Text(l10n.t("help_no_results")).foregroundStyle(.secondary)
                }
                ForEach(results) { a in
                    DisclosureGroup(isExpanded: Binding(get: { open == a.id }, set: { open = $0 ? a.id : nil })) {
                        Text(a.body(l10n.language))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .environment(\.layoutDirection, l10n.language == "ar" ? .rightToLeft : .leftToRight)
                    } label: {
                        Text(a.title(l10n.language)).font(.body.weight(.medium))
                    }
                }
            } header: {
                Text(l10n.t("help_common"))
            } footer: {
                if !["en", "ar"].contains(l10n.language) { Text(l10n.t("help_english_only")) }
            }

            Section {
                ForEach(SupportRequest.Kind.allCases, id: \.self) { kind in
                    NavigationLink { SupportFormView(kind: kind) } label: {
                        SettingsRow(icon: Self.icon(kind), tint: Self.tint(kind), title: l10n.t(Self.actionKey(kind)))
                    }
                }
            } header: {
                Text(l10n.t("help_contact_section"))
            } footer: {
                Text(l10n.t("help_reply_promise"))
            }

            if !history.isEmpty {
                Section(l10n.t("help_my_requests")) {
                    ForEach(history) { r in SentRequestRow(request: r) }
                }
            }
        }
        .searchable(text: $query, prompt: Text(l10n.t("help_search")))
        .navigationTitle(l10n.t("help_center"))
        .navigationBarTitleDisplayMode(.inline)
    }

    static func icon(_ k: SupportRequest.Kind) -> String {
        switch k {
        case .problem: "exclamationmark.bubble.fill"
        case .idea: "lightbulb.fill"
        case .question: "questionmark.bubble.fill"
        }
    }

    static func tint(_ k: SupportRequest.Kind) -> Color {
        switch k {
        case .problem: .red
        case .idea: .yellow
        case .question: .blue
        }
    }

    static func actionKey(_ k: SupportRequest.Kind) -> String {
        switch k {
        case .problem: "help_report_problem"
        case .idea: "help_suggest_idea"
        case .question: "help_ask_question"
        }
    }

    static func kindKey(_ k: SupportRequest.Kind) -> String { "help_kind_" + k.rawValue }
}

/// One thing the person sent: what kind, when, how it left, the reference to quote, and the message itself.
private struct SentRequestRow: View {
    @Environment(\.l10n) private var l10n
    let request: SupportRequest
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(request.message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t(HelpCenterView.kindKey(request.kind)) + " · " + request.sent.formatted(.dateTime.day().month().year().locale(l10n.locale)))
                    .font(.body.weight(.medium))
                Text(l10n.t("help_reference", request.id) + " · " + l10n.t("help_via_" + request.channel.rawValue))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Report a problem, Suggest an idea or Ask us a question: the message, the app and device lines (shown, and left
/// out with one switch), then email or copy. The request is kept on this device with its reference.
struct SupportFormView: View {
    @Environment(\.appModel) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @AppStorage(Help.historyKey) private var historyData = Data()
    let kind: SupportRequest.Kind
    @State private var message = ""
    @State private var includeDetails = true
    @State private var reference = SupportRequest.newReference()
    @State private var notice: String?
    @State private var sent: SupportRequest?
    @FocusState private var editing: Bool

    private var contact: HelpCenter.Contact {
        Help.center?.contact ?? HelpCenter.Contact(email: Publisher.email)
    }

    var body: some View {
        Form {
            if let sent {
                Section {
                    Label(l10n.t("help_reference", sent.id), systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green).textSelection(.enabled)
                    Text(l10n.t("help_reply_promise")).font(.callout)
                }
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(l10n.t("help_placeholder_" + kind.rawValue))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $message)
                        .frame(minHeight: 160)
                        .focused($editing)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                Text(l10n.t(HelpCenterView.actionKey(kind)))
            } footer: {
                Text(l10n.t("help_reference", reference)).monospacedDigit()
            }

            Section {
                Toggle(l10n.t("help_include_details"), isOn: $includeDetails)
                if includeDetails {
                    Text(details().joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            } footer: {
                Text(l10n.t("help_details_note"))
            }

            Section {
                Button { send(.email) } label: {
                    Label(l10n.t("help_send_email"), systemImage: "envelope.fill")
                }
                Button { send(.copied) } label: {
                    Label(l10n.t("help_copy"), systemImage: "doc.on.doc")
                }
            } footer: {
                if let notice { Text(notice) }
            }
        }
        .navigationTitle(l10n.t(HelpCenterView.actionKey(kind)))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// App, device, language, time zone and the calculation settings: what we need to reproduce a wrong time.
    /// Never the location or the city.
    private func details() -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info["CFBundleVersion"] as? String ?? "?") + ")"
        let device = UIDevice.current
        var lines = [
            "App: Mosque Pro " + version,
            "Device: \(device.model) · \(device.systemName) \(device.systemVersion)",
            "Language: \(l10n.language) · Time zone: \(app.settings.location?.zoneId ?? TimeZone.current.identifier)",
        ]
        let p = app.settings.prayer
        lines.append("Calculation: \(p.method.rawValue) · Asr: \(p.madhab.rawValue) · High latitude: \(p.highLatitudeRule.rawValue)")
        let offsets = PrayerEvent.allCases.compactMap { e in p.offsets[e].map { "\(e.rawValue) \($0 > 0 ? "+" : "")\($0)" } }
        if !offsets.isEmpty { lines.append("Minutes: " + offsets.joined(separator: ", ")) }
        if p.hijriAdjustmentDays != 0 { lines.append("Hijri: \(p.hijriAdjustmentDays > 0 ? "+" : "")\(p.hijriAdjustmentDays)") }
        if CleanNetwork.offered { lines.append("Clean network: \(CleanNetwork.shared.isOn ? "on" : "off")") }
        return lines
    }

    private func send(_ channel: SupportRequest.Channel) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            notice = l10n.t("help_message_empty")
            editing = true
            return
        }
        let r = SupportRequest(id: reference, kind: kind, message: text, details: includeDetails ? details() : [],
                               sent: Date(), channel: channel)
        let subject = r.subject(kindTitle: l10n.t(HelpCenterView.kindKey(kind)), appName: l10n.t("app_name"))
        switch channel {
        case .email:
            guard let url = r.mailURL(to: contact.email, subject: subject) else { return }
            openURL(url) { opened in
                if opened { done(r) } else { notice = l10n.t("help_no_mail", contact.email) }
            }
        case .whatsapp:
            return  // only in requests sent before WhatsApp was taken out
        case .copied:
            UIPasteboard.general.string = subject + "\n\n" + r.body
            notice = l10n.t("help_copied", contact.email)
            done(r)
        }
    }

    /// Kept on the device with its reference; the form is ready for the next message.
    private func done(_ r: SupportRequest) {
        historyData = SupportRequest.encodeList(SupportRequest.adding(r, to: SupportRequest.decodeList(historyData)))
        sent = r
        message = ""
        editing = false
        reference = SupportRequest.newReference()
    }
}
