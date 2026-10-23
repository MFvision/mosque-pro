import NMCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Verse of the day and Hadith of the day on the Prayer screen: the same for everyone on a date (Daily, NMCore
/// DailyContent). Arabic first; below it the translation in the interface language. Long-press to copy or share.
struct DailyCard: View {
    @Environment(\.l10n) private var l10n
    let content: DailyContent
    let now: Date
    let zone: TimeZone

    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let ayah = content.ayah(for: now, calendar: cal)
        let hadith = content.hadith(for: now, calendar: cal)
        return VStack(alignment: .leading, spacing: 14) {
            ayahView(ayah)
            Divider().overlay(Theme.ink.opacity(0.2))
            hadithView(hadith)
        }
        .foregroundStyle(Theme.ink)
        .glassCard()
    }

    private func ayahView(_ a: DailyContent.Ayah) -> some View {
        let ref = Daily.reference(a, language: l10n.language, locale: l10n.locale)
        let translation = a.translation(l10n.language)
        let shared = [a.ar, translation, ref].compactMap { $0 }.joined(separator: "\n\n")
        return VStack(alignment: .leading, spacing: 8) {
            Label(l10n.t("daily_ayah"), systemImage: "book.closed")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(a.ar)
                .font(.title3)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let t = translation {
                Text(t).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            Text(ref).font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
        }
        .contentShape(Rectangle())
        .contextMenu { actions(shared) }
        .accessibilityElement(children: .combine)
    }

    private func hadithView(_ h: DailyContent.Hadith) -> some View {
        let text = h.text(l10n.language)
        let note = "\(text.grade) · \(text.source)"
        let shared = [l10n.language == "ar" ? nil : h.ar.text, text.text, note, h.url].compactMap { $0 }.joined(separator: "\n\n")
        return VStack(alignment: .leading, spacing: 8) {
            Label(l10n.t("daily_hadith"), systemImage: "quote.bubble")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            Text("«\(text.text)»").font(.body).fixedSize(horizontal: false, vertical: true)
            Text(note).font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
            Text("HadeethEnc.com").font(.caption2).foregroundStyle(Theme.ink.opacity(0.55))
        }
        .contentShape(Rectangle())
        .contextMenu { actions(shared) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ text: String) -> some View {
        Button(l10n.t("copy_answer"), systemImage: "doc.on.doc") {
            #if os(iOS) || os(visionOS)
            UIPasteboard.general.string = text
            #endif
        }
        ShareLink(item: text)
    }
}
