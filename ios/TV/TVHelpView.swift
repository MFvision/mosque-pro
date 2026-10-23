import CoreImage
import CoreImage.CIFilterBuiltins
import NMCore
import SwiftUI

/// Settings → Help on Apple TV: a QR code that opens WhatsApp on the person's phone with a message to us already
/// started (the reference, the app's version and tvOS), the email address, and the answers that apply to the TV.
struct TVHelpView: View {
    @Environment(TVModel.self) private var model
    @State private var reference = SupportRequest.newReference()

    static let center: HelpCenter? = Bundle.main.url(forResource: "help", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? HelpCenter.load($0) }

    var body: some View {
        let l10n = model.l10n
        let help = Self.center
        List {
            if let help {
                Section {
                    HStack(alignment: .center, spacing: 60) {
                        if let url = whatsApp(help.contact), let qr = Self.qr(url.absoluteString) {
                            Image(decorative: qr, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 300, height: 300)
                                .padding(20)
                                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            Text(l10n.t("help_tv_scan")).font(.system(size: 34, weight: .semibold))
                            Text(l10n.t("help_tv_or_email", help.contact.email)).font(.system(size: 28))
                            Text(l10n.t("help_reference", reference)).font(.system(size: 26)).foregroundStyle(.secondary).monospacedDigit()
                            Text(l10n.t("help_reply_promise")).font(.system(size: 24)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 20)
                    // Focusable so the remote can reach this row and the list can scroll past it.
                    .focusable()
                }
                Section(l10n.t("help_common")) {
                    ForEach(help.articles(for: .tv)) { a in
                        NavigationLink(a.title(l10n.language)) {
                            ScrollView {
                                Text(a.body(l10n.language))
                                    .font(.system(size: 32))
                                    .frame(maxWidth: 1300, alignment: .leading)
                                    .padding(60)
                                    .focusable()
                            }
                            .navigationTitle(a.title(l10n.language))
                        }
                    }
                }
            }
        }
        .navigationTitle(l10n.t("help_center"))
    }

    /// WhatsApp on the phone, the message started with the reference and what we need to know about the TV.
    private func whatsApp(_ contact: HelpCenter.Contact) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info["CFBundleVersion"] as? String ?? "?") + ")"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let r = SupportRequest(id: reference, kind: .question, message: "",
                               details: ["App: Mosque Pro \(version) · Apple TV · tvOS \(os.majorVersion).\(os.minorVersion)",
                                         "Language: \(model.l10n.language)"],
                               sent: Date(), channel: .whatsapp)
        return r.whatsAppURL(number: contact.whatsapp, subject: "[\(reference)] Apple TV · \(model.l10n.t("app_name"))")
    }

    /// A sharp QR code for a link (CoreImage draws one pixel per module; SwiftUI scales it without blurring).
    static func qr(_ text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let image = f.outputImage else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}
