import NMCore
import SwiftUI

/// The picture for one side of a question: drawn in 140 × 200 points (light tiles, navy line, gold accents) and scaled
/// to fit. Each one moves a little while it is on screen (the dot pulses, the shadow grows, the bell rings, the ads get
/// swept); none of it under Reduce Motion, in still screenshots, or in the pile. Never mirrored.
struct PairArt: View {
    let question: PairQuestion
    let side: Int
    var look: WidgetLook?
    var playing = false
    var rtl = false
    var animated = true
    @Environment(\.onb) private var onb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t = false

    private var moving: Bool { animated && !onb.still && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 140, geo.size.height / 200)
            drawing
                .frame(width: 140, height: 200)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: 140 * k, height: 200 * k, alignment: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(PairInk.tile)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .onAppear {
            guard moving else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.3)) { t = true }
        }
    }

    // A rounded bar at x, y (its top left), w × h.
    private func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color, r: CGFloat = 3) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(c).frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }

    @ViewBuilder private var drawing: some View {
        switch question {
        case .place: if side == 0 { near } else { city }
        case .asr: asr(two: side == 1)
        case .voice: if side == 0 { makkah } else { madinah }
        case .alarm: if side == 0 { banner } else { alarm }
        case .appearance: PairHome(dark: side == 1, accent: nil, background: nil)
        case .style, .styleFinal: style(look ?? .cream)
        case .friday: if side == 0 { friday } else { quietFriday }
        case .clean: if side == 0 { ads } else { clean }
        }
    }

    // MARK: Place

    private var near: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: -10, y: 60)); p.addCurve(to: CGPoint(x: 150, y: 55), control1: CGPoint(x: 40, y: 70), control2: CGPoint(x: 90, y: 40))
                p.move(to: CGPoint(x: 30, y: -10)); p.addCurve(to: CGPoint(x: 45, y: 210), control1: CGPoint(x: 40, y: 60), control2: CGPoint(x: 20, y: 130))
                p.move(to: CGPoint(x: -10, y: 150)); p.addCurve(to: CGPoint(x: 150, y: 140), control1: CGPoint(x: 50, y: 140), control2: CGPoint(x: 100, y: 165))
            }
            .stroke(Color(hex: 0xD3DCE3), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 100, y: -10)); p.addLine(to: CGPoint(x: 110, y: 210))
                p.move(to: CGPoint(x: -10, y: 105)); p.addLine(to: CGPoint(x: 150, y: 112))
            }
            .stroke(Color(hex: 0xE6ECF0), lineWidth: 4)
            Circle().fill(PairInk.gold.opacity(t ? 0 : 0.35))
                .frame(width: 52, height: 52)
                .scaleEffect(t ? 1.6 : 0.5)
                .position(x: 70, y: 98)
            Circle().fill(.white).frame(width: 22, height: 22).position(x: 70, y: 98)
            Circle().fill(PairInk.ink).frame(width: 14, height: 14).position(x: 70, y: 98)
        }
    }

    private var city: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(.white).overlay(Capsule().strokeBorder(PairInk.line)).frame(width: 116, height: 30).position(x: 70, y: 35)
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(PairInk.ink)
                .position(x: rtl ? 113 : 27, y: 35)
            bar(rtl ? 62 : 40, 32, 34, 6, PairInk.ink)
            bar(rtl ? 58 : 76, 29, 1.5, 13, PairInk.gold, r: 0.75).opacity(t ? 0.15 : 1)
            ForEach(0..<4, id: \.self) { i in
                let y = 64 + CGFloat(i) * 32
                let first = i == 0
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(first ? Color.white : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(first ? PairInk.gold : .clear))
                    .frame(width: 116, height: 26).position(x: 70, y: y + 13)
                Circle().fill(first ? PairInk.gold : PairInk.muted).frame(width: 7, height: 7).position(x: rtl ? 114 : 26, y: y + 13)
                let w = CGFloat([58, 44, 50, 38][i])
                bar(rtl ? 106 - w : 38, y + 9, w, 5, first ? PairInk.ink : PairInk.muted, r: 2.5)
            }
        }
    }

    // MARK: Asr

    private func asr(two: Bool) -> some View {
        let sun = two ? CGPoint(x: 120, y: 62) : CGPoint(x: 96, y: 42)
        let shadow: CGFloat = two ? 54 : 28
        return ZStack(alignment: .topLeading) {
            Path { p in p.move(to: CGPoint(x: 10, y: 150)); p.addLine(to: CGPoint(x: 130, y: 150)) }
                .stroke(PairInk.ink, lineWidth: 1.5)
            Circle().fill(PairInk.gold.opacity(0.15)).frame(width: 36, height: 36).position(sun)
            Circle().fill(PairInk.gold).frame(width: 22, height: 22).position(sun)
            Path { p in p.move(to: sun); p.addLine(to: CGPoint(x: 60 - shadow, y: 150)) }
                .stroke(PairInk.gold, style: StrokeStyle(lineWidth: 1.3, dash: [2, 4]))
            // The shadow grows from the foot of the stick to one or two lengths.
            RoundedRectangle(cornerRadius: 2.5).fill(PairInk.ink.opacity(0.28))
                .frame(width: shadow, height: 5)
                .scaleEffect(x: grown ? 1 : 0.02, y: 1, anchor: .trailing)
                .position(x: 60 - shadow / 2, y: 150)
                .onAppear {
                    guard moving else { return }
                    withAnimation(PairInk.out.delay(0.35)) { grown = true }
                }
            bar(58, two ? 122 : 118, 4, two ? 28 : 32, PairInk.ink, r: 2)
            Text(two ? "×2" : "×1").font(.system(size: 13, weight: .bold)).foregroundStyle(PairInk.ink).position(x: 70, y: 180)
        }
    }

    @State private var grown = false

    // MARK: Adhan voice

    private func waves(_ y: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array([14, 24, 32, 22, 12].enumerated()), id: \.offset) { i, h in
                Capsule().fill(PairInk.gold)
                    .frame(width: 5, height: CGFloat(h))
                    .scaleEffect(y: playing && t ? (i % 2 == 0 ? 0.4 : 1) : (playing ? 0.7 : 1), anchor: .center)
                    .animation(playing && moving ? .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.1) : .default, value: t)
            }
        }
        .frame(width: 140, height: 40)
        .position(x: 70, y: y)
    }

    private var makkah: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 22, y: 132)); p.addLine(to: CGPoint(x: 70, y: 112)); p.addLine(to: CGPoint(x: 118, y: 132))
                p.addLine(to: CGPoint(x: 118, y: 76)); p.addLine(to: CGPoint(x: 70, y: 58)); p.addLine(to: CGPoint(x: 22, y: 76)); p.closeSubpath()
            }
            .fill(Color(hex: 0x1B1F24))
            Path { p in
                p.move(to: CGPoint(x: 22, y: 76)); p.addLine(to: CGPoint(x: 70, y: 94)); p.addLine(to: CGPoint(x: 118, y: 76))
                p.move(to: CGPoint(x: 70, y: 94)); p.addLine(to: CGPoint(x: 70, y: 112))
            }
            .stroke(Color(hex: 0x3A4048), lineWidth: 1)
            Path { p in p.move(to: CGPoint(x: 22, y: 86)); p.addLine(to: CGPoint(x: 70, y: 104)); p.addLine(to: CGPoint(x: 118, y: 86)) }
                .stroke(PairInk.gold, lineWidth: 5)
            Path { p in
                p.move(to: CGPoint(x: 58, y: 128)); p.addLine(to: CGPoint(x: 58, y: 114)); p.addLine(to: CGPoint(x: 66, y: 117)); p.addLine(to: CGPoint(x: 66, y: 131)); p.closeSubpath()
            }
            .fill(PairInk.gold.opacity(0.9))
            waves(166)
        }
    }

    private var madinah: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white).overlay(Rectangle().strokeBorder(PairInk.line)).frame(width: 72, height: 40).position(x: 70, y: 116)
            Path { p in p.addArc(center: CGPoint(x: 70, y: 96), radius: 26, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false); p.closeSubpath() }
                .fill(PairInk.green)
            bar(68, 56, 4, 16, PairInk.gold, r: 1)
            Circle().fill(PairInk.gold).frame(width: 7, height: 7).position(x: 70, y: 54)
            ForEach([20.5, 119.5], id: \.self) { (x: Double) in
                Rectangle().fill(.white).overlay(Rectangle().strokeBorder(PairInk.line)).frame(width: 9, height: 72).position(x: x, y: 100)
                Path { p in
                    p.move(to: CGPoint(x: x - 6.5, y: 64)); p.addLine(to: CGPoint(x: x, y: 48)); p.addLine(to: CGPoint(x: x + 6.5, y: 64)); p.closeSubpath()
                }
                .fill(PairInk.green)
            }
            bar(52, 112, 10, 24, Color(hex: 0xD9E1E7), r: 5)
            bar(78, 112, 10, 24, Color(hex: 0xD9E1E7), r: 5)
            waves(166)
        }
    }

    // MARK: Notification or alarm

    private func clock(_ y: CGFloat, _ text: String) -> some View {
        Text(text).font(.system(size: 34, weight: .light)).monospacedDigit().foregroundStyle(PairInk.ink).position(x: 70, y: y)
    }

    private func notice(_ y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PairInk.line))
                .frame(width: 120, height: 44).position(x: 70, y: y + 22)
            bar(20, y + 12, 20, 20, PairInk.ink, r: 6)
            Circle().fill(PairInk.gold).frame(width: 8, height: 8).position(x: 30, y: y + 22)
            bar(48, y + 13, 56, 6, PairInk.ink)
            bar(48, y + 25, 70, 4.5, PairInk.muted, r: 2.25)
        }
        .offset(y: dropped || !moving ? 0 : -34)
        .opacity(dropped || !moving ? 1 : 0)
        .onAppear {
            guard moving else { return }
            withAnimation(PairInk.out.delay(0.35)) { dropped = true }
        }
    }

    @State private var dropped = false

    private var banner: some View {
        ZStack(alignment: .topLeading) {
            clock(56, "3:12")
            notice(80)
        }
    }

    private var alarm: some View {
        ZStack(alignment: .topLeading) {
            clock(60, "3:12")
            Image(systemName: "bell.fill")
                .font(.system(size: 34))
                .foregroundStyle(PairInk.gold)
                .symbolEffect(.wiggle, options: .repeating, isActive: moving)
                .position(x: 70, y: 106)
            Capsule().fill(PairInk.ink).frame(width: 92, height: 24).position(x: 70, y: 152)
            bar(52, 149, 36, 6, .white)
            Capsule().fill(.white).overlay(Capsule().strokeBorder(PairInk.line)).frame(width: 92, height: 20).position(x: 70, y: 180)
        }
    }

    // MARK: Look

    private func style(_ look: WidgetLook) -> some View {
        let solid = SolidTheme.of(look.rawValue)
        let bg = solid.map { $0.tokens(dark: true).background } ?? Color(hex: 0xF5F7F9)
        return PairHome(dark: solid != nil, accent: solid != nil ? StyleAccent.dark(look.rawValue) : StyleAccent.light(look.rawValue), background: bg)
    }

    // MARK: Friday

    private var friday: some View {
        ZStack(alignment: .topLeading) {
            notice(24)
            Path { p in
                p.move(to: CGPoint(x: 36, y: 94)); p.addQuadCurve(to: CGPoint(x: 70, y: 94), control: CGPoint(x: 70, y: 82))
                p.addLine(to: CGPoint(x: 70, y: 168)); p.addQuadCurve(to: CGPoint(x: 36, y: 168), control: CGPoint(x: 70, y: 156)); p.closeSubpath()
            }
            .fill(PairInk.green)
            Path { p in
                p.move(to: CGPoint(x: 104, y: 94)); p.addQuadCurve(to: CGPoint(x: 70, y: 94), control: CGPoint(x: 70, y: 82))
                p.addLine(to: CGPoint(x: 70, y: 168)); p.addQuadCurve(to: CGPoint(x: 104, y: 168), control: CGPoint(x: 70, y: 156)); p.closeSubpath()
            }
            .fill(Color(hex: 0x357D52))
            RoundedRectangle(cornerRadius: 2).strokeBorder(PairInk.gold, lineWidth: 1.4).frame(width: 20, height: 50).position(x: 54, y: 130)
            RoundedRectangle(cornerRadius: 2).strokeBorder(PairInk.gold, lineWidth: 1.4).frame(width: 20, height: 50).position(x: 86, y: 130)
        }
    }

    private var quietFriday: some View {
        ZStack(alignment: .topLeading) {
            clock(92, "12:05")
            Text("FRI").font(.system(size: 10, weight: .semibold)).kerning(2).foregroundStyle(PairInk.muted).position(x: 70, y: 118)
            Image(systemName: "bell.slash")
                .font(.system(size: 13))
                .foregroundStyle(PairInk.muted)
                .frame(width: 28, height: 28)
                .background(.white, in: Circle())
                .overlay(Circle().strokeBorder(PairInk.line))
                .position(x: 70, y: 150)
        }
    }

    // MARK: Clean network

    private var ads: some View {
        ZStack(alignment: .topLeading) {
            bar(10, 14, 120, 40, Color(hex: 0xF26B5B), r: 8)
            Text("AD").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).position(x: 70, y: 34)
            bar(10, 62, 104, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 72, 84, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 86, 120, 48, Color(hex: 0xF5B145), r: 8)
            Text("AD").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).position(x: 70, y: 110)
            bar(10, 144, 96, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 154, 70, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 166, 120, 22, Color(hex: 0x8B6CF2), r: 8)
        }
    }

    private var clean: some View {
        ZStack(alignment: .topLeading) {
            bar(10, 16, 104, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 26, 84, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 36, 96, 5, Color(hex: 0xC3CDD5), r: 2.5)
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(PairInk.line))
                .frame(width: 120, height: 66).position(x: 70, y: 85)
            Path { p in
                p.move(to: CGPoint(x: 24, y: 104)); p.addLine(to: CGPoint(x: 46, y: 78)); p.addLine(to: CGPoint(x: 62, y: 94))
                p.addLine(to: CGPoint(x: 74, y: 82)); p.addLine(to: CGPoint(x: 96, y: 104))
            }
            .stroke(PairInk.muted, lineWidth: 2)
            bar(10, 128, 100, 5, Color(hex: 0xC3CDD5), r: 2.5)
            bar(10, 138, 72, 5, Color(hex: 0xC3CDD5), r: 2.5)
            // A soft sweep across the page.
            Rectangle().fill(.white.opacity(0.55))
                .frame(width: 40, height: 240)
                .rotationEffect(.degrees(12))
                .position(x: t ? 200 : -60, y: 100)
                .opacity(moving ? 1 : 0)
            Circle().fill(PairInk.ink).frame(width: 36, height: 36).position(x: 108, y: 168)
            Image(systemName: "checkmark.shield.fill").font(.system(size: 16)).foregroundStyle(PairInk.gold).position(x: 108, y: 168)
        }
    }
}

/// A small Mosque Pro home: the next prayer card and four prayer rows, the second one marked, in light, dark or a style.
struct PairHome: View {
    let dark: Bool
    let accent: Color?
    let background: Color?

    var body: some View {
        let bg = background ?? (dark ? Color(hex: 0x0E1A24) : Color(hex: 0xF5F7F9))
        let card = dark ? Color.white.opacity(0.09) : .white
        let text = dark ? Color(hex: 0xEEF2F5) : PairInk.ink
        let sub = dark ? Color(hex: 0x7C8C99) : Color(hex: 0x9AA8B3)
        let a = accent ?? (dark ? PairInk.gold : Color(hex: 0x8A6A1C))
        ZStack(alignment: .topLeading) {
            bg
            row(10, 16, 120, 70, card, 16)
            row(20, 28, 34, 5, a, 2.5)
            row(20, 40, 74, 13, text, 4)
            row(20, 60, 48, 5, sub, 2.5)
            Path { p in p.addArc(center: CGPoint(x: 112, y: 88), radius: 28, startAngle: .degrees(200), endAngle: .degrees(290), clockwise: false) }
                .stroke(a, lineWidth: 2)
            Circle().fill(a).frame(width: 8, height: 8).position(x: 114, y: 62)
            ForEach(0..<4, id: \.self) { i in
                let y = 96 + CGFloat(i) * 24
                let marked = i == 1
                row(10, y, 120, 19, marked ? a.opacity(0.18) : card, 7)
                row(18, y + 7, CGFloat([30, 26, 34, 24][i]), 5, marked ? a : sub, 2.5)
                row(104, y + 7, 18, 5, marked ? a : sub, 2.5)
            }
        }
        .frame(width: 140, height: 200)
    }

    private func row(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color, _ r: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(c).frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }
}
