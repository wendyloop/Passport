import SwiftUI

// 4:5 card carousel templates (v3), ported 1:1 from the approved preview
// (scratchpad carousel-previews.html) which was itself composed from the
// nine Instagram reference posts. Every slide renders as a 390×488-design
// card scaled to the device width, sitting on the shared dark ground —
// the way the reference posts sit in Instagram's feed — with the apply
// controls living below on the ground, never over the art.
//
// Layout style: absolute placement in the 390×488 design space (topLeading
// ZStack + offsets), mirroring the preview's HTML coordinates so what was
// approved is what ships. Typography uses the bundled faces registered by
// CarouselFonts.

// MARK: - Slide router

struct CardTemplateSlideView: View {
    let slide: CarouselSlide
    let style: CarouselStyle
    let job: JobPostingRecord
    let onEmailFounder: (() -> Void)?

    var body: some View {
        // Instagram framing: the art runs the full device width with square
        // corners, vertically centered in the space above the apply
        // controls — the dark ground is just letterboxing, not a border.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CardCanvas {
                content
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 230)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch slide {
        case .cover(let s):
            cover(s)
        case .aboutCompany(let s):
            interior(CardInterior(
                kicker: "the backstory",
                title: s.company ?? job.displayCompanyName,
                rows: aboutRows(s),
                pill: nil,
                order: s.order
            ))
        case .role(let s):
            interior(CardInterior(kicker: nil, title: "what you'd actually do",
                                  rows: s.bullets.prefix(4).map { CardRow($0) }, pill: comp, order: s.order))
        case .requirements(let s):
            interior(CardInterior(kicker: nil, title: "you're a fit if",
                                  rows: s.bullets.prefix(4).map { CardRow($0) }, pill: nil, order: s.order))
        case .perks(let s):
            interior(CardInterior(kicker: nil, title: "the good stuff",
                                  rows: s.bullets.prefix(4).map { CardRow($0) }, pill: comp, order: s.order))
        case .founder(let s):
            interior(CardInterior(
                kicker: job.displayCompanyName,
                title: "meet \(firstName(s)) 👋",
                rows: [
                    CardRow([s.name, s.roleTitle].compactMap { $0 }.joined(separator: " · ")),
                    CardRow("your pitch lands in their inbox — not an ATS black hole."),
                ],
                pill: onEmailFounder != nil ? "pitch \(firstName(s))" : nil,
                order: s.order,
                pillAction: onEmailFounder
            ))
        case .details(let s):
            interior(CardInterior(kicker: job.displayCompanyName, title: "the deets",
                                  rows: detailRows(s), pill: comp, order: s.order))
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func cover(_ s: CoverSlide) -> some View {
        switch style.archetype {
        case .boldDrop:         BoldDropCard.cover(s, job)
        case .sundayEdit:       SundayEditCard.cover(s, job)
        case .motionEditorial:  MotionEditorialCard.cover(s, job)
        case .stickerScrapbook: StickerScrapbookCard.cover(s, job)
        case .daydreamY2K:      DaydreamY2KCard.cover(s, job)
        case .handPainted:      HandPaintedCard.cover(s, job)
        case .quietLuxury:      QuietLuxuryCard.cover(s, job)
        default:                EmptyView()
        }
    }

    @ViewBuilder
    private func interior(_ c: CardInterior) -> some View {
        switch style.archetype {
        case .boldDrop:         BoldDropCard.interior(c)
        case .sundayEdit:       SundayEditCard.interior(c)
        case .motionEditorial:  MotionEditorialCard.interior(c)
        case .stickerScrapbook: StickerScrapbookCard.interior(c)
        case .daydreamY2K:      DaydreamY2KCard.interior(c)
        case .handPainted:      HandPaintedCard.interior(c)
        case .quietLuxury:      QuietLuxuryCard.interior(c)
        default:                EmptyView()
        }
    }

    private var comp: String? {
        job.compensationSummary ?? job.compensationText
    }

    private func firstName(_ s: FounderSlide) -> String {
        s.name?.split(separator: " ").first.map(String.init) ?? "the founder"
    }

    private func aboutRows(_ s: AboutCompanySlide) -> [CardRow] {
        var rows: [CardRow] = []
        if let blurb = s.blurb { rows.append(CardRow(blurb)) }
        let facts = [s.industry, s.stage?.replacingOccurrences(of: "_", with: " "),
                     s.backedBy.map { "backed by \($0)" }].compactMap { $0 }
        if !facts.isEmpty { rows.append(CardRow(facts.joined(separator: " · "))) }
        return Array(rows.prefix(3))
    }

    private func detailRows(_ s: DetailsSlide) -> [CardRow] {
        var rows: [CardRow] = []
        if let loc = s.location ?? job.location { rows.append(CardRow(loc, sub: "location")) }
        if let emp = s.employment ?? job.employmentType?.title { rows.append(CardRow(emp, sub: "type")) }
        if let comp = s.compensation ?? job.compensationText { rows.append(CardRow(comp, sub: "compensation")) }
        for perk in (s.perks ?? []).prefix(max(0, 4 - rows.count)) { rows.append(CardRow(perk, sub: "perk")) }
        return Array(rows.prefix(4))
    }
}

// One interior slide, template-agnostic: a kicker, a title, up to four
// rows, and an optional accent pill (a real CTA on the founder slide).
struct CardRow {
    let text: String
    let sub: String?
    init(_ text: String, sub: String? = nil) { self.text = text; self.sub = sub }
}

struct CardInterior {
    let kicker: String?
    let title: String
    let rows: [CardRow]
    let pill: String?
    let order: Int
    var pillAction: (() -> Void)? = nil
}

// MARK: - Canvas (design space 390×488, scaled to fit)

private let designW: CGFloat = 390
private let designH: CGFloat = 487.5

struct CardCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / designW
            ZStack(alignment: .topLeading) { content() }
                .frame(width: designW, height: designH)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(designW / designH, contentMode: .fit)
        // Hard crop, square corners — an IG post, not a floating card.
        .clipped()
    }
}

private extension View {
    /// HTML-style absolute placement in the card's design space.
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { offset(x: x, y: y) }
}

// MARK: - Shared card doodads

/// Five-point sticker star with a cream halo and dark outline (T3).
struct StickerStar: View {
    var size: CGFloat
    var fill: Color
    var rotation: Double = 0

    var body: some View {
        ZStack {
            Star5Shape().stroke(Color(red: 0.99, green: 0.98, blue: 0.94), style: StrokeStyle(lineWidth: size * 0.16, lineJoin: .round))
            Star5Shape().fill(fill)
            Star5Shape().stroke(Color(red: 0.17, green: 0.17, blue: 0.17), style: StrokeStyle(lineWidth: size * 0.05, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
    }
}

struct Star5Shape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (50, 4), (62, 36), (96, 38), (69, 59), (79, 93),
            (50, 72), (21, 93), (31, 59), (4, 38), (38, 36),
        ]
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + pts[0].0 / 100 * rect.width, y: rect.minY + pts[0].1 / 100 * rect.height))
        for (x, y) in pts.dropFirst() {
            p.addLine(to: CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height))
        }
        p.closeSubpath()
        return p
    }
}

/// Twelve-point spark (T5 doodle).
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (50, 0), (58, 38), (95, 25), (64, 50), (95, 75), (58, 62),
            (50, 100), (42, 62), (5, 75), (36, 50), (5, 25), (42, 38),
        ]
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + pts[0].0 / 100 * rect.width, y: rect.minY + pts[0].1 / 100 * rect.height))
        for (x, y) in pts.dropFirst() {
            p.addLine(to: CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height))
        }
        p.closeSubpath()
        return p
    }
}

/// Approximated outline text (no native stroke in SwiftUI): eight offset
/// copies of the stroke color behind the fill. Fine at sticker sizes.
struct StrokedText: View {
    let text: String
    let font: Font
    let fill: Color
    let stroke: Color
    var strokeWidth: CGFloat = 2

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                Text(text).font(font)
                    .foregroundStyle(stroke)
                    .offset(x: cos(angle) * strokeWidth, y: sin(angle) * strokeWidth)
            }
            Text(text).font(font).foregroundStyle(fill)
        }
    }
}

/// Cover title split into stacked uppercase words, capped at three lines.
private func titleLines(_ s: CoverSlide, _ job: JobPostingRecord, cap: Int = 3) -> [String] {
    let words = (s.role ?? job.title).uppercased().split(separator: " ").map(String.init)
    guard words.count > cap else { return words }
    var lines = Array(words.prefix(cap - 1))
    lines.append(words.dropFirst(cap - 1).joined(separator: " "))
    return lines
}

private func coverComp(_ s: CoverSlide, _ job: JobPostingRecord) -> String? {
    s.compensation ?? job.compensationSummary ?? job.compensationText
}

private func coverMeta(_ s: CoverSlide, _ job: JobPostingRecord) -> String {
    [coverComp(s, job), s.location ?? job.location, s.workMode]
        .compactMap { $0 }.prefix(3).joined(separator: " · ")
}

// MARK: - 00 · Bold drop (after @rishabh_job)

enum BoldDropCard {
    static let cream = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let navy = Color(red: 0.11, green: 0.16, blue: 0.27)
    static let red = Color(red: 0.91, green: 0.25, blue: 0.11)
    static let teal = Color(red: 0.12, green: 0.35, blue: 0.40)

    static func partPill(_ text: String) -> some View {
        Text(text)
            .font(CarouselFonts.archivoBold(11))
            .foregroundStyle(cream)
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Capsule().fill(teal))
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            cream
            partPill("part 1").at(18, 18)
            Text("scout22").font(CarouselFonts.archivoBold(12)).tracking(1)
                .foregroundStyle(navy)
                .frame(width: designW - 18, alignment: .trailing).at(0, 20)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(titleLines(s, job).enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(CarouselFonts.archivoBlack(52))
                        .foregroundStyle(i == 1 ? red : navy)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            .frame(width: 354, alignment: .leading).at(18, 100)
            Text("at \(job.displayCompanyName) · \(coverMeta(s, job))")
                .font(CarouselFonts.archivoBold(12.5))
                .foregroundStyle(navy)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 354, alignment: .leading).at(18, 296)
            Text("⟶  SWIPE TO EXPLORE")
                .font(CarouselFonts.archivoBold(11)).tracking(2)
                .foregroundStyle(red).at(18, 436)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            cream
            partPill("part \(c.order)").at(18, 18)
            (Text(c.title.uppercased()).foregroundColor(navy))
                .font(CarouselFonts.archivoBlack(24))
                .lineLimit(2).minimumScaleFactor(0.6)
                .frame(width: 354, alignment: .leading).at(18, 58)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Rectangle().fill(navy).frame(height: 2)
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", i + 1))
                                .font(CarouselFonts.archivoBlack(14)).foregroundStyle(red)
                                .padding(.top, 2)
                            Text(row.text)
                                .font(CarouselFonts.archivoBold(15))
                                .foregroundStyle(navy)
                                .lineLimit(2).minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(width: 354, alignment: .leading).at(18, 128)
            bottomLine(c).at(18, 436)
        }
    }

    @ViewBuilder
    private static func bottomLine(_ c: CardInterior) -> some View {
        // Founder slide gets a live CTA; other slides get no footer — the
        // real apply controls sit right below the card.
        if let pill = c.pill, let action = c.pillAction {
            Button(action: action) {
                Text("⟶  \(pill.uppercased())")
                    .font(CarouselFonts.archivoBold(11)).tracking(2).foregroundStyle(red)
            }
        }
    }
}

// MARK: - 01 · Sunday edit (after @janelabrahami)

enum SundayEditCard {
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.89)
    static let plum = Color(red: 0.36, green: 0.10, blue: 0.20)
    static let lavender = Color(red: 0.73, green: 0.76, blue: 0.90)
    static let chartreuse = Color(red: 0.86, green: 0.89, blue: 0.42)

    static func photoBlock(_ w: CGFloat, _ h: CGFloat, _ rot: Double, _ colors: [Color]) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: w, height: h)
            .rotationEffect(.degrees(rot))
            .shadow(color: plum.opacity(0.18), radius: 9, y: 4)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            cream
            photoBlock(120, 85, 2, [Color(red: 0.89, green: 0.80, blue: 0.66), Color(red: 0.55, green: 0.41, blue: 0.27)]).at(228, 18)
            photoBlock(95, 110, -2, [Color(red: 0.94, green: 0.89, blue: 0.82), Color(red: 0.70, green: 0.60, blue: 0.47)]).at(-20, 148)
            Text("✦").font(.system(size: 32)).foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.18))
                .shadow(color: Color(red: 0.66, green: 0.48, blue: 0.08), radius: 0, y: 2).at(318, 96)
            VStack(spacing: 2) {
                let lines = titleLines(s, job)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    if i == 1 {
                        Text(line).font(CarouselFonts.archivoBlackItalic(33))
                            .foregroundStyle(plum)
                            .padding(.horizontal, 7)
                            .background(lavender)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                        Text(line).font(CarouselFonts.archivoBlackItalic(i == 0 ? 30 : 33))
                            .foregroundStyle(plum)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                Text("at \(job.displayCompanyName) — \(s.location ?? job.location ?? "remote")")
                    .font(CarouselFonts.playfairItalic(14))
                    .foregroundStyle(plum)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 9)
            }
            .frame(width: designW).at(0, 186)
            photoBlock(95, 75, -2, [Color(red: 0.85, green: 0.80, blue: 0.75), Color(red: 0.56, green: 0.59, blue: 0.66)]).at(35, 352)
            if let comp = coverComp(s, job) {
                VStack(spacing: 0) {
                    Text(comp).font(CarouselFonts.playfairBoldItalic(16)).foregroundStyle(plum)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("/yr!").font(CarouselFonts.playfairItalic(12)).foregroundStyle(plum)
                }
                .frame(width: 94, height: 94)
                .background(Circle().fill(chartreuse))
                .overlay(Circle().stroke(plum, lineWidth: 2))
                .rotationEffect(.degrees(-8))
                .at(242, 338)
            }
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            cream
            HStack(alignment: .firstTextBaseline) {
                Text("SCOUT22 · \(c.kicker?.uppercased() ?? "THE DETAILS")")
                    .font(CarouselFonts.dmMono(9.5)).tracking(2.5)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("no. 0\(c.order)").font(CarouselFonts.playfairItalic(19))
            }
            .foregroundStyle(plum)
            .frame(width: 342).at(24, 20)
            (Text(c.title.uppercased()).foregroundColor(plum))
                .font(CarouselFonts.archivoExtraBoldItalic(22))
                .lineLimit(2).minimumScaleFactor(0.6)
                .frame(width: 342, alignment: .leading).at(24, 62)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Rectangle().fill(plum).frame(height: 2)
                        Text(row.text.uppercased())
                            .font(CarouselFonts.archivoExtraBoldItalic(13))
                            .foregroundStyle(plum)
                            .lineLimit(2).minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        if let sub = row.sub {
                            Text(sub).font(CarouselFonts.playfairItalic(12.5))
                                .foregroundStyle(plum.opacity(0.7))
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
            .frame(width: 342, alignment: .leading).at(24, 118)
            if let pill = c.pill {
                pillView(pill, action: c.pillAction).at(24, 428)
            }
        }
    }

    @ViewBuilder
    private static func pillView(_ text: String, action: (() -> Void)?) -> some View {
        let label = Text(text).font(CarouselFonts.dmMono(11)).foregroundStyle(plum)
            .padding(.horizontal, 15).padding(.vertical, 5)
            .background(Capsule().fill(chartreuse))
        if let action { Button(action: action) { label } } else { label }
    }
}

// MARK: - 02 · Motion editorial (after @afastaffing)

enum MotionEditorialCard {
    static let bone = Color(red: 0.92, green: 0.91, blue: 0.89)
    static let ink = Color(red: 0.08, green: 0.07, blue: 0.06)

    static func season(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let year = Calendar.current.component(.year, from: date)
        let name: String
        switch month {
        case 3...5: name = "Spring"
        case 6...8: name = "Summer"
        case 9...11: name = "Autumn"
        default: name = "Winter"
        }
        return "\(name) \(year)"
    }

    static func figure() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.13), Color(red: 0.29, green: 0.26, blue: 0.23)], startPoint: .top, endPoint: .bottom))
                .frame(width: 165, height: 265)
                .blur(radius: 11)
                .opacity(0.92)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.76, green: 0.60, blue: 0.48), Color(red: 0.56, green: 0.42, blue: 0.32)], center: .center, startRadius: 2, endRadius: 30))
                .frame(width: 60, height: 60)
                .blur(radius: 8)
                .offset(x: -15, y: -85)
        }
        .rotationEffect(.degrees(-4))
    }

    static func vertical(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(CarouselFonts.playfair(size)).tracking(2)
            .foregroundStyle(ink)
            .fixedSize()
            .rotationEffect(.degrees(90))
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            bone
            figure().at(42, 8)
            Text("01").font(CarouselFonts.italianno(54)).foregroundStyle(ink).at(278, -4)
            VStack(alignment: .leading, spacing: -4) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line).font(CarouselFonts.archivoBlack(44))
                        .foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            .frame(width: 310, alignment: .leading).at(22, 248)
            Text(coverMeta(s, job).uppercased())
                .font(CarouselFonts.dmMono(10.5)).tracking(4)
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 330, alignment: .leading).at(22, 410)
            vertical(season(job.createdAt), size: 24).at(300, 210)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            bone
            Text("0\(c.order)").font(CarouselFonts.italianno(54)).foregroundStyle(ink).at(20, -6)
            VStack(alignment: .leading, spacing: 0) {
                Text(c.title.uppercased())
                    .font(CarouselFonts.archivoBlack(30))
                    .foregroundStyle(ink)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if let kicker = c.kicker {
                    Text("at \(kicker) — moving fast")
                        .font(CarouselFonts.playfairItalic(15))
                        .foregroundStyle(ink)
                        .padding(.top, 10)
                }
                Rectangle().fill(ink).frame(width: 180, height: 2).padding(.vertical, 16)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
                        Text("— \(row.text.uppercased())")
                            .font(CarouselFonts.dmMono(11)).tracking(1)
                            .foregroundStyle(ink)
                            .lineLimit(2).minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let pill = c.pill {
                    pillView(pill, action: c.pillAction).padding(.top, 18)
                }
            }
            .frame(width: 300, alignment: .leading).at(22, 88)
        }
    }

    @ViewBuilder
    private static func pillView(_ text: String, action: (() -> Void)?) -> some View {
        let label = Text(text.uppercased())
            .font(CarouselFonts.archivoBold(11)).tracking(3)
            .foregroundStyle(bone)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Rectangle().fill(ink))
        if let action { Button(action: action) { label } } else { label }
    }
}

// MARK: - 03 · Sticker scrapbook (after @bloomsburypulse)

enum StickerScrapbookCard {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let olive = Color(red: 0.56, green: 0.52, blue: 0.24)
    static let brown = Color(red: 0.29, green: 0.27, blue: 0.15)
    static let blue = Color(red: 0.68, green: 0.80, blue: 0.92)
    static let pink = Color(red: 0.95, green: 0.72, blue: 0.78)
    static let sand = Color(red: 0.91, green: 0.87, blue: 0.63)

    static var ground: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.65, green: 0.28, blue: 0.25), location: 0),
                    .init(color: Color(red: 0.70, green: 0.31, blue: 0.28), location: 0.52),
                    .init(color: Color(red: 0.75, green: 0.60, blue: 0.42), location: 0.53),
                    .init(color: Color(red: 0.65, green: 0.50, blue: 0.32), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color(red: 0.84, green: 0.41, blue: 0.37)).frame(width: 200, height: 85)
                .blur(radius: 18).opacity(0.7).at(-30, 14)
            Ellipse().fill(Color(red: 0.56, green: 0.23, blue: 0.20)).frame(width: 180, height: 75)
                .blur(radius: 16).opacity(0.8).at(220, 28)
        }
    }

    static func bubble(_ text: String, size: CGFloat) -> some View {
        StrokedText(text: text, font: CarouselFonts.balooExtraBold(size),
                    fill: Color(red: 0.98, green: 0.97, blue: 0.94), stroke: olive, strokeWidth: 2)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            VStack(spacing: 1) {
                Text("@\(job.displayCompanyName.lowercased().replacingOccurrences(of: " ", with: ""))")
                    .font(CarouselFonts.balooBold(12)).foregroundStyle(brown)
                    .padding(.horizontal, 11).padding(.vertical, 1)
                    .background(Capsule().fill(blue))
                    .rotationEffect(.degrees(-2))
                    .padding(.bottom, 3)
                ForEach(Array(titleLines(s, job).enumerated()), id: \.offset) { i, line in
                    bubble(line.lowercased(), size: i == 0 ? 37 : 36)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Text(coverMeta(s, job).uppercased())
                    .font(CarouselFonts.balooSemiBold(10.5)).tracking(2.5)
                    .foregroundStyle(olive)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 6)
            }
            .frame(width: 334, height: 246)
            .background(RoundedRectangle(cornerRadius: 7).fill(paper).shadow(color: .black.opacity(0.38), radius: 14, y: 7))
            .rotationEffect(.degrees(-1))
            .at(28, 92)
            StickerStar(size: 52, fill: blue, rotation: -12).at(6, 62)
            StickerStar(size: 38, fill: pink, rotation: 14).at(52, 22)
            StickerStar(size: 46, fill: blue, rotation: 8).at(318, 308)
            Text("swipe!").font(CarouselFonts.balooExtraBold(15)).foregroundStyle(brown)
                .padding(.horizontal, 17).padding(.vertical, 2)
                .background(Capsule().fill(blue))
                .rotationEffect(.degrees(7))
                .at(276, 398)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        let tilts: [Double] = [-1.5, 1.2, -1, 1.4]
        let fills: [Color] = [pink, blue, sand, pink]
        return ZStack(alignment: .topLeading) {
            ground
            Text(c.title.lowercased())
                .font(CarouselFonts.balooExtraBold(13.5)).foregroundStyle(brown)
                .padding(.horizontal, 17).padding(.vertical, 3)
                .background(Capsule().fill(paper).shadow(color: .black.opacity(0.3), radius: 9, y: 4))
                .rotationEffect(.degrees(-2))
                .at(100, 18)
            VStack(spacing: 16) {
                ForEach(Array(c.rows.prefix(3).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            StickerStar(size: 20, fill: fills[i % fills.count], rotation: Double(i * 30))
                            Text(row.text.lowercased())
                                .font(CarouselFonts.balooExtraBold(15))
                                .foregroundStyle(brown)
                                .lineLimit(2).minimumScaleFactor(0.7)
                        }
                        if let sub = row.sub {
                            Text(sub).font(CarouselFonts.gochiHand(13)).foregroundStyle(olive)
                        }
                        if i == 0, let pill = c.pill {
                            Text(pill)
                                .font(CarouselFonts.balooBold(11.5)).foregroundStyle(brown)
                                .padding(.horizontal, 11).padding(.vertical, 1)
                                .background(Capsule().fill(fills[i % fills.count]))
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .frame(width: 330, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(paper).shadow(color: .black.opacity(0.3), radius: 10, y: 5))
                    .rotationEffect(.degrees(tilts[i % tilts.count]))
                }
            }
            .at(30, 68)
            ctaPill(c).at(76, 428)
        }
    }

    @ViewBuilder
    private static func ctaPill(_ c: CardInterior) -> some View {
        // Only the founder slide carries a footer pill (a live pitch CTA).
        if let action = c.pillAction, let pill = c.pill {
            Button(action: action) {
                Text(pill)
                    .font(CarouselFonts.balooExtraBold(14)).foregroundStyle(brown)
                    .padding(.horizontal, 18).padding(.vertical, 2)
                    .background(Capsule().fill(blue))
                    .rotationEffect(.degrees(-3))
            }
        }
    }
}

// MARK: - 04 · Daydream Y2K (after @skysociety.co)

enum DaydreamY2KCard {
    static let skyTop = Color(red: 0.56, green: 0.66, blue: 0.88)
    static let skyMid = Color(red: 0.72, green: 0.79, blue: 0.93)
    static let skyBot = Color(red: 0.65, green: 0.73, blue: 0.91)
    static let pinkPill = Color(red: 0.89, green: 0.34, blue: 0.55)
    static let creamPill = Color(red: 0.96, green: 0.93, blue: 0.75)
    static let pillBlue = Color(red: 0.43, green: 0.55, blue: 0.82)
    static let cardInk = Color(red: 0.20, green: 0.32, blue: 0.56)

    static func cloud(_ w: CGFloat, _ h: CGFloat, _ o: Double) -> some View {
        Ellipse().fill(.white).frame(width: w, height: h).blur(radius: 16).opacity(o)
    }

    static func pill(_ text: String, dark: Bool, rot: Double) -> some View {
        Text(text)
            .font(CarouselFonts.archivoBoldItalic(13))
            .foregroundStyle(dark ? .white : pillBlue)
            .lineLimit(1)
            .padding(.horizontal, 13).padding(.vertical, 4)
            .background(Capsule().fill(dark ? pinkPill : creamPill).shadow(color: pillBlue.opacity(0.35), radius: 6, y: 3))
            .rotationEffect(.degrees(rot))
    }

    static func pixel(_ text: String, size: CGFloat, rot: Double) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let dx: CGFloat = i % 2 == 0 ? 1.2 : -1.2
                let dy: CGFloat = i < 2 ? 1.2 : -1.2
                Text(text).font(CarouselFonts.vt323(size)).foregroundStyle(.white).offset(x: dx, y: dy)
            }
            Text(text).font(CarouselFonts.vt323(size)).foregroundStyle(pinkPill)
        }
        .rotationEffect(.degrees(rot))
    }

    static var ground: some View {
        LinearGradient(stops: [
            .init(color: skyTop, location: 0), .init(color: skyMid, location: 0.55),
            .init(color: skyBot, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            cloud(170, 80, 0.85).at(-50, 30)
            cloud(170, 85, 0.7).at(240, 12)
            cloud(190, 90, 0.75).at(30, 298)
            cloud(170, 85, 0.85).at(230, 372)
            Text("scout22").font(CarouselFonts.archivoBold(12)).tracking(5)
                .foregroundStyle(.white)
                .frame(width: designW).at(0, 22)
            VStack(spacing: -2) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line).font(CarouselFonts.archivoBlack(38))
                        .foregroundStyle(.white)
                        .shadow(color: pillBlue.opacity(0.55), radius: 8, y: 4)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(width: designW).at(0, 132)
            if let comp = coverComp(s, job) { pill(comp, dark: true, rot: -7).at(24, 82) }
            if let loc = s.location ?? job.location { pill(loc.lowercased(), dark: false, rot: 5).at(252, 108) }
            if let exp = s.experience { pill(CoverFacts.experienceLabel(exp), dark: false, rot: 4).at(32, 328) }
            pill("at \(job.displayCompanyName.lowercased())", dark: true, rot: -4).at(212, 362)
            pixel("i <3 startups", size: 14, rot: 4).at(212, 60)
            pixel("s22", size: 17, rot: -6).at(326, 298)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            cloud(150, 75, 0.7).at(-40, 10)
            cloud(160, 80, 0.75).at(260, 390)
            Text(c.title.uppercased())
                .font(CarouselFonts.archivoBlack(24))
                .foregroundStyle(.white)
                .shadow(color: pillBlue.opacity(0.5), radius: 6, y: 3)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: designW).at(0, 30)
            VStack(spacing: 12) {
                ForEach(Array(c.rows.prefix(3).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.text)
                            .font(CarouselFonts.archivoBold(15.5))
                            .foregroundStyle(cardInk)
                            .lineLimit(2).minimumScaleFactor(0.75)
                        if let sub = row.sub {
                            Text(sub).font(CarouselFonts.archivoBold(11.5)).foregroundStyle(pillBlue)
                        }
                        if i == 0, let pillText = c.pill {
                            Text(pillText)
                                .font(CarouselFonts.archivoBold(11)).foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 2)
                                .background(Capsule().fill(pinkPill))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 15).padding(.vertical, 12)
                    .frame(width: 330, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.93)).shadow(color: pillBlue.opacity(0.3), radius: 8, y: 4))
                }
            }
            .at(30, 82)
            pixel("tap tap hired ✶", size: 19, rot: -2)
                .frame(width: designW).at(0, 418)
        }
    }
}

// MARK: - 05 · Hand-painted (after @eleanorbowmer)

enum HandPaintedCard {
    static let butter = Color(red: 0.97, green: 0.89, blue: 0.61)
    static let cardCream = Color(red: 0.99, green: 0.97, blue: 0.89)
    static let palette: [Color] = [
        Color(red: 0.78, green: 0.61, blue: 0.88), Color(red: 0.91, green: 0.70, blue: 0.24),
        Color(red: 0.89, green: 0.34, blue: 0.54), Color(red: 0.25, green: 0.54, blue: 0.35),
        Color(red: 0.36, green: 0.50, blue: 0.85), Color(red: 0.85, green: 0.26, blue: 0.23),
    ]

    static func painted(_ text: String, size: CGFloat, offset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(CarouselFonts.chewy(size))
                    .foregroundStyle(ch == " " ? .clear : palette[(i + offset) % palette.count])
            }
        }
        .lineLimit(1).minimumScaleFactor(0.4)
    }

    static func spark(_ size: CGFloat, _ color: Color, _ rot: Double) -> some View {
        SparkShape().fill(color).frame(width: size, height: size).rotationEffect(.degrees(rot))
    }

    static var eye: some View {
        ZStack {
            DoodleEyeShape().fill(Color(red: 1, green: 0.99, blue: 0.96))
            DoodleEyeShape().stroke(Color(red: 0.17, green: 0.17, blue: 0.17), lineWidth: 3)
            Circle().fill(Color(red: 0.36, green: 0.50, blue: 0.85)).frame(width: 26, height: 26).offset(y: 3)
            Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.12)).frame(width: 12, height: 12).offset(y: 3)
            Circle().fill(.white).frame(width: 5, height: 5).offset(x: 4, y: -2)
        }
        .frame(width: 82, height: 46)
    }

    static var cherries: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 19, y: 34))
                p.addQuadCurve(to: CGPoint(x: 40, y: 6), control: CGPoint(x: 24, y: 10))
                p.move(to: CGPoint(x: 37, y: 35))
                p.addQuadCurve(to: CGPoint(x: 40, y: 6), control: CGPoint(x: 33, y: 13))
            }
            .stroke(Color(red: 0.29, green: 0.44, blue: 0.85), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            Circle().fill(Color(red: 0.85, green: 0.26, blue: 0.23)).frame(width: 25, height: 25).at(6, 32)
            Circle().fill(Color(red: 0.85, green: 0.26, blue: 0.23)).frame(width: 22, height: 22).at(28, 36)
        }
        .frame(width: 58, height: 60)
    }

    static var flower: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Ellipse()
                    .fill(Color(red: 0.18, green: 0.37, blue: 0.82))
                    .frame(width: 24, height: 15)
                    .offset(x: 18)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(Color(red: 0.25, green: 0.54, blue: 0.35)).frame(width: 20, height: 20)
        }
        .frame(width: 64, height: 64)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            butter
            eye.at(22, 28)
            spark(30, Color(red: 0.56, green: 0.71, blue: 0.91), 0).at(276, 26)
            spark(21, palette[2], 20).at(178, 62)
            spark(24, palette[5], -10).at(24, 130)
            spark(30, palette[1], 12).at(342, 122)
            VStack(spacing: 8) {
                let lines = titleLines(s, job)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    painted(line, size: 42, offset: i * 2)
                }
                Text("at \(job.displayCompanyName.lowercased()) · \(coverMeta(s, job).lowercased())")
                    .font(CarouselFonts.balooSemiBold(12.5))
                    .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.14))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)
            }
            .frame(width: designW).at(0, 158)
            cherries.at(46, 362)
            spark(24, palette[3], 0).at(176, 368)
            flower.at(272, 356)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            butter
            painted(c.title.uppercased(), size: 26, offset: 1)
                .frame(width: designW).at(0, 22)
            VStack(spacing: 14) {
                ForEach(Array(c.rows.prefix(3).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            spark(17, palette[(i * 2 + 2) % palette.count], 0)
                            Text(row.text.lowercased())
                                .font(CarouselFonts.chewy(17))
                                .foregroundStyle(palette[(i * 2 + 2) % palette.count])
                                .lineLimit(2).minimumScaleFactor(0.7)
                        }
                        if i == 0, let pill = c.pill {
                            Text(pill).font(CarouselFonts.chewy(14))
                                .foregroundStyle(palette[5])
                        } else if let sub = row.sub {
                            Text(sub).font(CarouselFonts.balooSemiBold(12))
                                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.14))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .frame(width: 330, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(cardCream).shadow(color: Color(red: 0.47, green: 0.35, blue: 0.08).opacity(0.2), radius: 7, y: 3))
                }
            }
            .at(30, 74)
            cherries.scaleEffect(0.86).at(112, 336)
            spark(22, palette[1], 15).at(222, 344)
            if let action = c.pillAction {
                Button(action: action) {
                    painted("pitch the founder", size: 18, offset: 3)
                }
                .frame(width: designW).at(0, 428)
            }
        }
    }
}

struct DoodleEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0.05 * w, y: 0.55 * h))
        p.addQuadCurve(to: CGPoint(x: 0.95 * w, y: 0.55 * h), control: CGPoint(x: 0.5 * w, y: -0.1 * h))
        p.addQuadCurve(to: CGPoint(x: 0.05 * w, y: 0.55 * h), control: CGPoint(x: 0.5 * w, y: 1.05 * h))
        p.closeSubpath()
        return p
    }
}

// MARK: - 06 · Quiet luxury (after @missempowher)

enum QuietLuxuryCard {
    static let greigeTop = Color(red: 0.89, green: 0.85, blue: 0.80)
    static let greigeBot = Color(red: 0.78, green: 0.72, blue: 0.64)
    static let creamInk = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let darkInk = Color(red: 0.18, green: 0.16, blue: 0.13)
    static let softInk = Color(red: 0.43, green: 0.38, blue: 0.33)

    static var ground: some View {
        LinearGradient(colors: [greigeTop, greigeBot], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var figure: some View {
        RoundedRectangle(cornerRadius: 78, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.21, blue: 0.18), Color(red: 0.38, green: 0.33, blue: 0.28)], startPoint: .top, endPoint: .bottom))
            .frame(width: 150, height: 275)
            .blur(radius: 16)
            .opacity(0.65)
            .rotationEffect(.degrees(3))
    }

    static func capsule(_ text: String, color: Color, action: (() -> Void)? = nil) -> some View {
        let label = Text(text)
            .font(CarouselFonts.archivoBold(10)).tracking(2.5)
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .frame(width: 260)
            .padding(.vertical, 9)
            .background(Capsule().stroke(color, lineWidth: 1.5))
        return Group {
            if let action { Button(action: action) { label } } else { label }
        }
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            figure.at(118, 34)
            Text("s22").font(CarouselFonts.italianno(30)).foregroundStyle(creamInk)
                .frame(width: designW).at(0, 12)
            VStack(spacing: -2) {
                Text(job.displayCompanyName.uppercased())
                    .font(CarouselFonts.playfairBold(42)).tracking(1)
                    .foregroundStyle(creamInk)
                    .shadow(color: darkInk.opacity(0.25), radius: 6, y: 2)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text("is hiring.")
                    .font(CarouselFonts.playfairItalic(32))
                    .foregroundStyle(creamInk)
                    .shadow(color: darkInk.opacity(0.25), radius: 6, y: 2)
            }
            .frame(width: 360).at(15, 150)
            capsule((s.role ?? job.title).uppercased(), color: creamInk).at(65, 308)
            Text(coverMeta(s, job).uppercased())
                .font(CarouselFonts.dmMono(9)).tracking(2.5)
                .foregroundStyle(creamInk)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: designW).at(0, 362)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            HStack {
                Text("SCOUT22 EDIT")
                Spacer()
                Text("0\(c.order)")
            }
            .font(CarouselFonts.dmMono(9)).tracking(2.5)
            .foregroundStyle(softInk)
            .frame(width: 334).at(28, 20)
            VStack(alignment: .leading, spacing: 0) {
                if let kicker = c.kicker {
                    Text(kicker).font(CarouselFonts.playfairItalic(19)).foregroundStyle(softInk)
                }
                Text(c.title.uppercased())
                    .font(CarouselFonts.playfairBold(34))
                    .foregroundStyle(darkInk)
                    .lineLimit(2).minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Rectangle().fill(darkInk).frame(width: 74, height: 1.5).padding(.vertical, 16)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
                        Text(row.text.uppercased())
                            .font(CarouselFonts.dmMono(10.5)).tracking(1.5)
                            .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.23))
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 334, alignment: .leading).at(28, 88)
            if let pill = c.pill {
                capsule(pill.uppercased(), color: darkInk, action: c.pillAction).at(65, 408)
            }
        }
    }
}
