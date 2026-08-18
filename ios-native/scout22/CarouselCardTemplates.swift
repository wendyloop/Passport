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
    // Grid-tile previews render just the card, no feed letterboxing.
    var previewMode: Bool = false

    var body: some View {
        if previewMode {
            CardCanvas {
                content
            }
        } else {
            // Instagram framing: the art runs the full device width with square
            // corners, vertically centered in the space above the apply
            // controls — the dark ground is just letterboxing, not a border.
            // The top padding biases the card ~1cm (60pt) below true center,
            // per product review.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                CardCanvas {
                    content
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 120)
            .padding(.bottom, 230)
            .frame(maxWidth: .infinity)
        }
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

    // Both routers are type-erased on purpose. As a @ViewBuilder switch these
    // build a _ConditionalContent tree one level deep per case, and at fifteen
    // archetypes that crashed swift-frontend during SIL lowering (hit adding
    // the second reference set, 2026-08-16). AnyView flattens it, and the cost
    // is nothing next to the blurs and gradients these templates already draw.
    // Keep them erased when adding archetypes.
    private func cover(_ s: CoverSlide) -> AnyView {
        switch style.archetype {
        case .boldDrop:         return AnyView(BoldDropCard.cover(s, job))
        case .sundayEdit:       return AnyView(SundayEditCard.cover(s, job))
        case .motionEditorial:  return AnyView(MotionEditorialCard.cover(s, job))
        case .stickerScrapbook: return AnyView(StickerScrapbookCard.cover(s, job))
        case .daydreamY2K:      return AnyView(DaydreamY2KCard.cover(s, job))
        case .handPainted:      return AnyView(HandPaintedCard.cover(s, job))
        case .quietLuxury:      return AnyView(QuietLuxuryCard.cover(s, job))
        case .warmMinimal:      return AnyView(WarmMinimalCard.cover(s, job))
        case .afterHours:       return AnyView(AfterHoursCard.cover(s, job))
        case .boutiqueSerif:    return AnyView(BoutiqueSerifCard.cover(s, job))
        case .pressClipping:    return AnyView(PressClippingCard.cover(s, job))
        case .panelPlate:       return AnyView(PanelPlateCard.cover(s, job))
        case .marqueePoster:    return AnyView(MarqueePosterCard.cover(s, job))
        case .folderTabs:       return AnyView(FolderTabsCard.cover(s, job))
        case .motionSplit:      return AnyView(MotionSplitCard.cover(s, job))
        }
    }

    private func interior(_ c: CardInterior) -> AnyView {
        switch style.archetype {
        case .boldDrop:         return AnyView(BoldDropCard.interior(c))
        case .sundayEdit:       return AnyView(SundayEditCard.interior(c))
        case .motionEditorial:  return AnyView(MotionEditorialCard.interior(c))
        case .stickerScrapbook: return AnyView(StickerScrapbookCard.interior(c))
        case .daydreamY2K:      return AnyView(DaydreamY2KCard.interior(c))
        case .handPainted:      return AnyView(HandPaintedCard.interior(c))
        case .quietLuxury:      return AnyView(QuietLuxuryCard.interior(c))
        case .warmMinimal:      return AnyView(WarmMinimalCard.interior(c))
        case .afterHours:       return AnyView(AfterHoursCard.interior(c))
        case .boutiqueSerif:    return AnyView(BoutiqueSerifCard.interior(c))
        case .pressClipping:    return AnyView(PressClippingCard.interior(c))
        case .panelPlate:       return AnyView(PanelPlateCard.interior(c))
        case .marqueePoster:    return AnyView(MarqueePosterCard.interior(c))
        case .folderTabs:       return AnyView(FolderTabsCard.interior(c))
        case .motionSplit:      return AnyView(MotionSplitCard.interior(c))
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
        return rows
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

// `coverComp` and `coverMeta` retired 2026-08-15. It joined comp/location/work-mode into one
// string that every cover drew with .lineLimit(1) and a .minimumScaleFactor
// as low as 0.5, so type size became a function of how long the location
// happened to be. Replaced by FactRail below, which drops cells instead.

/// Horizontal rail of labelled facts, in the template's own palette and face.
///
/// The contract every cover shares: cells are equal width, divided by a
/// hairline rather than a middot, ordered by `CoverFacts.rail`, and the value
/// clamps at 0.85 — past that the lowest-priority cell is dropped by `max`
/// instead of shrinking. So the fourth cell is always the level, whichever
/// cover a job lands on.
struct FactRail: View {
    let facts: [CardFact]
    let labelFont: Font
    let valueFont: Font
    let ink: Color
    /// Busy-art templates pass 3; the rest take the default 4.
    var maxCells: Int = 4
    var width: CGFloat = 354
    /// Templates whose label ink needs to differ from a dimmed value ink.
    var labelInk: Color? = nil
    var ruleOpacity: Double = 0.25

    private var topCount: Int { min(maxCells, facts.count) }

    /// Cells are sized to their content, never to equal fractions of the
    /// width: "San Francisco" needs more room than "Hybrid", and equal
    /// quarters truncated the long one to "San Franc…" while the short one
    /// sat in empty space.
    private func row(_ count: Int, compressible: Bool = false) -> some View {
        let shown = Array(facts.prefix(count))
        return HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    Rectangle()
                        .fill(ink.opacity(ruleOpacity))
                        .frame(width: 1, height: 32)
                        .padding(.trailing, 11)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label.uppercased())
                        .font(labelFont)
                        .tracking(1.1)
                        .foregroundStyle(labelInk ?? ink.opacity(0.62))
                    Text(fact.value)
                        .font(valueFont)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(compressible ? 0.7 : 1)
                }
                .fixedSize(horizontal: !compressible, vertical: false)
                .padding(.trailing, index == shown.count - 1 ? 0 : 11)
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        // Drop from the right until the row fits, rather than scaling the
        // type down — the ladder is why a long location can never shrink the
        // facts again. The final rung is allowed to compress, so a single
        // very long value still renders instead of overflowing the card.
        ViewThatFits(in: .horizontal) {
            row(topCount)
            row(max(topCount - 1, 1))
            row(max(topCount - 2, 1))
            row(1, compressible: true)
        }
        .frame(width: width, alignment: .leading)
    }
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
            Text("at \(job.displayCompanyName)")
                .font(CarouselFonts.archivoBold(15))
                .foregroundStyle(teal)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 354, alignment: .leading).at(18, 296)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: CarouselFonts.archivoBold(14),
                ink: navy
            ).at(18, 340)
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
                // Location moved to the rail, trimmed to the city; leaving it
                // here as well printed the raw "San Francisco, CA, United
                // States" twice on one card.
                Text("at \(job.displayCompanyName)")
                    .font(CarouselFonts.playfairItalic(14))
                    .foregroundStyle(plum)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 9)
            }
            .frame(width: designW).at(0, 186)
            // The pay circle and the third photo block both lived where the
            // rail now sits; comp moved into the rail, so both are gone.
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: CarouselFonts.archivoExtraBoldItalic(13.5),
                ink: plum
            ).at(18, 404)
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
            // The company name never appeared on this cover at all; the rail
            // freed the room the old meta line was using.
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.dmMono(11)).tracking(3)
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 300, alignment: .leading).at(22, 214)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: CarouselFonts.archivoBlack(13),
                ink: ink
            ).at(22, 398)
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
            }
            .frame(width: 334, height: 246)
            .background(RoundedRectangle(cornerRadius: 7).fill(paper).shadow(color: .black.opacity(0.38), radius: 14, y: 7))
            .rotationEffect(.degrees(-1))
            .at(28, 92)
            StickerStar(size: 52, fill: blue, rotation: -12).at(6, 62)
            StickerStar(size: 38, fill: pink, rotation: 14).at(52, 22)
            StickerStar(size: 46, fill: blue, rotation: 8).at(318, 308)
            // Three cells: the stars and the swipe pill leave less clear width
            // here than the flatter templates have.
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.balooSemiBold(8),
                valueFont: CarouselFonts.balooExtraBold(14),
                ink: paper,
                maxCells: 3,
                width: 330,
                ruleOpacity: 0.35
            ).at(30, 352)
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
            // The four scattered rotated pills carried these same facts at
            // four different angles; the rail sets them on one baseline.
            Text("at \(job.displayCompanyName.lowercased())")
                .font(CarouselFonts.archivoBoldItalic(15))
                .foregroundStyle(.white)
                .shadow(color: pillBlue.opacity(0.6), radius: 6, y: 2)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: designW).at(0, 302)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.archivoBold(7.5),
                valueFont: CarouselFonts.archivoBoldItalic(14),
                ink: .white,
                labelInk: .white.opacity(0.85),
                ruleOpacity: 0.45
            ).at(18, 346)
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
                Text("at \(job.displayCompanyName.lowercased())")
                    .font(CarouselFonts.balooSemiBold(12.5))
                    .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.14))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)
            }
            // Chewy sets on a tall line box, so the three title lines plus the
            // company line run to ~370 — the block starts higher to clear the
            // rail rather than the rail moving down onto the doodles.
            .frame(width: designW).at(0, 128)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.balooSemiBold(7.5),
                valueFont: CarouselFonts.chewy(15),
                ink: Color(red: 0.72, green: 0.26, blue: 0.18),
                labelInk: Color(red: 0.42, green: 0.36, blue: 0.14)
            ).at(18, 350)
            cherries.at(46, 396)
            spark(24, palette[3], 0).at(176, 402)
            flower.at(272, 394)
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
            // "is hiring." dropped 2026-08-15 — filler. The company stays the
            // headline and the role stays in the capsule, which keeps this
            // template company-forward and distinct from warmMinimal, the
            // other centred-serif card it shares the earthy pool with.
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.playfairBold(42)).tracking(1)
                .foregroundStyle(creamInk)
                .shadow(color: darkInk.opacity(0.25), radius: 6, y: 2)
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(width: 360).at(15, 150)
            capsule((s.role ?? job.title).uppercased(), color: creamInk).at(65, 308)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: CarouselFonts.playfairBold(14),
                ink: creamInk,
                ruleOpacity: 0.4
            ).at(18, 376)
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

// MARK: - 07 · Warm minimal (after @kellishoponline)

enum WarmMinimalCard {
    static let bgTop = Color(red: 0.91, green: 0.84, blue: 0.72)
    static let bgBot = Color(red: 0.87, green: 0.79, blue: 0.66)
    static let card = Color(red: 0.96, green: 0.92, blue: 0.83)
    static let ink = Color(red: 0.17, green: 0.14, blue: 0.08)
    static let softInk = Color(red: 0.54, green: 0.46, blue: 0.33)
    static let italicInk = Color(red: 0.36, green: 0.30, blue: 0.20)

    static var ground: some View {
        LinearGradient(colors: [bgTop, bgBot], startPoint: .top, endPoint: .bottom)
    }

    /// Sunlit still life: striped curtain light, dark vases, a table — the
    /// cover's whole backdrop, drawn with plain shapes like the reference.
    static var scene: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.86, green: 0.77, blue: 0.62), bgTop],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 83, height: designH)
            HStack(spacing: 0) {
                ForEach(0..<23, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0
                              ? Color(red: 0.97, green: 0.94, blue: 0.86)
                              : Color(red: 0.93, green: 0.87, blue: 0.75))
                        .frame(width: 8.8)
                }
            }
            .frame(width: 202, height: 368)
            .blur(radius: 0.5)
            .shadow(color: Color(red: 0.97, green: 0.94, blue: 0.86).opacity(0.55), radius: 43)
            .at(101, 51)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.37, green: 0.32, blue: 0.28), Color(red: 0.24, green: 0.20, blue: 0.17)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 47, height: 119)
                .at(43, 231)
            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5, topTrailingRadius: 5)
                .fill(Color(red: 0.18, green: 0.15, blue: 0.13))
                .frame(width: 40, height: 47)
                .rotationEffect(.degrees(2))
                .at(47, 188)
            Ellipse()
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.90, blue: 0.80), Color(red: 0.85, green: 0.78, blue: 0.64)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 170, height: 43)
                .shadow(color: Color(red: 0.35, green: 0.27, blue: 0.16).opacity(0.2), radius: 11, y: 7)
                .at(137, 318)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.35, blue: 0.29), Color(red: 0.31, green: 0.24, blue: 0.20)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 21, height: 116)
                .at(211, 350)
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 12)
                .fill(Color(red: 0.29, green: 0.23, blue: 0.19))
                .frame(width: 25, height: 40)
                .at(239, 285)
        }
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            scene
            Text("SCOUT22")
                .font(CarouselFonts.dmMono(8)).tracking(3)
                .foregroundStyle(softInk)
                .frame(width: designW).at(0, 20)
            VStack(spacing: 2) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line)
                        .font(CarouselFonts.playfair(40)).tracking(2.2)
                        .foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
                Text("at \(job.displayCompanyName)")
                    .font(CarouselFonts.playfairItalic(15))
                    .foregroundStyle(italicInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 8)
            }
            .frame(width: designW - 40).at(20, 78)
            // The still life runs under the rail here, so it sits on a cream
            // plate — the same treatment this template's interior slides use.
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: CarouselFonts.playfair(15),
                ink: ink,
                width: 314,
                labelInk: softInk
            )
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(card.opacity(0.92))
                    .shadow(color: Color(red: 0.35, green: 0.27, blue: 0.16).opacity(0.16), radius: 14, y: 4)
            )
            .at(26, 412)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            Rectangle()
                .fill(card)
                .frame(width: 311, height: 412)
                .shadow(color: Color(red: 0.35, green: 0.27, blue: 0.16).opacity(0.25), radius: 22, y: 9)
                .at(40, 38)
            VStack(spacing: 0) {
                Text("\((c.kicker ?? "SCOUT22").uppercased()) — 0\(c.order)")
                    .font(CarouselFonts.dmMono(9)).tracking(3.6)
                    .foregroundStyle(softInk)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(c.title.uppercased())
                    .font(CarouselFonts.playfair(30)).tracking(1)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 17)
                Rectangle().fill(ink).frame(width: 40, height: 2)
                    .padding(.vertical, 18)
                VStack(spacing: 12) {
                    ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
                        VStack(spacing: 2) {
                            Text(row.text)
                                .font(CarouselFonts.playfairItalic(16))
                                .foregroundStyle(italicInk)
                                .multilineTextAlignment(.center)
                                .lineLimit(2).minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                            if let sub = row.sub {
                                Text(sub.uppercased())
                                    .font(CarouselFonts.dmMono(8.5)).tracking(2)
                                    .foregroundStyle(softInk)
                            }
                        }
                    }
                }
            }
            .frame(width: 280).at(55, 78)
            bottomLine(c).at(40, 415)
        }
    }

    @ViewBuilder
    private static func bottomLine(_ c: CardInterior) -> some View {
        if let pill = c.pill, let action = c.pillAction {
            Button(action: action) {
                Text(pill.uppercased())
                    .font(CarouselFonts.dmMono(9)).tracking(2.9)
                    .foregroundStyle(ink)
                    .frame(width: 220)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(ink, lineWidth: 1.5))
                    .frame(width: 311)
            }
        } else if let pill = c.pill {
            Text(pill.uppercased())
                .font(CarouselFonts.dmMono(8.7)).tracking(2.9)
                .foregroundStyle(softInk)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 311)
        }
    }
}

// MARK: - 08 · After hours (after @weauroracreatives)

enum AfterHoursCard {
    static let gold = Color(red: 0.94, green: 0.85, blue: 0.54)
    static let dimText = Color(red: 0.79, green: 0.80, blue: 0.76)

    static var ground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.15, green: 0.17, blue: 0.19), location: 0),
                .init(color: Color(red: 0.11, green: 0.12, blue: 0.14), location: 0.55),
                .init(color: Color(red: 0.08, green: 0.09, blue: 0.10), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func blob(_ w: CGFloat, _ h: CGFloat, _ colors: [Color], blur: CGFloat, opacity: Double, rotation: Double = 0, circle: Bool = false) -> some View {
        Group {
            if circle {
                Circle().fill(colors[0]).frame(width: w, height: h)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h)
            }
        }
        .rotationEffect(.degrees(rotation))
        .blur(radius: blur)
        .opacity(opacity)
    }

    static func arrow(width: CGFloat) -> some View {
        HStack(spacing: 1) {
            Rectangle().fill(gold).frame(width: width, height: 1.2)
            Image(systemName: "arrowtriangle.forward.fill")
                .font(.system(size: 6))
                .foregroundStyle(gold)
        }
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            blob(130, 343, [Color(red: 0.71, green: 0.41, blue: 0.24), Color(red: 0.43, green: 0.24, blue: 0.13)], blur: 19, opacity: 0.8, rotation: -5).at(-61, 29)
            blob(144, 202, [Color(red: 0.21, green: 0.27, blue: 0.24)], blur: 23, opacity: 0.75).at(209, 87)
            blob(108, 108, [Color(red: 0.16, green: 0.21, blue: 0.17)], blur: 17, opacity: 0.8, circle: true).at(119, 260)
            blob(108, 123, [Color(red: 0.18, green: 0.16, blue: 0.14)], blur: 18, opacity: 0.9).at(303, 343)
            VStack(spacing: 4) {
                Text("EST. NYC")
                    .font(CarouselFonts.dmMono(7)).tracking(2.2)
                HStack(spacing: 12) {
                    Text("VIDEO-FIRST").font(CarouselFonts.dmMono(7)).tracking(1.4)
                    Text("s22").font(CarouselFonts.archivoBold(23)).tracking(0.7)
                    Text("JOB DISCOVERY").font(CarouselFonts.dmMono(7)).tracking(1.4)
                }
            }
            .foregroundStyle(gold)
            .frame(width: designW).at(0, 38)
            VStack(spacing: -4) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line.lowercased())
                        .font(.system(size: 44, weight: .light)).tracking(0.7)
                        .foregroundStyle(gold)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            .frame(width: designW - 40).at(20, 178)
            // Was a right-aligned stack 152pt wide, which forced the meta line
            // down to a 0.5 scale factor — the worst offender of the nine.
            HStack(spacing: 8) {
                arrow(width: 54)
                Text(job.displayCompanyName.uppercased())
                    .font(CarouselFonts.dmMono(9.7)).tracking(1.4)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(gold)
            .frame(width: 325, alignment: .leading).at(32, 352)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: .system(size: 17, weight: .light),
                ink: gold,
                labelInk: dimText,
                ruleOpacity: 0.35
            ).at(18, 398)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            blob(152, 188, [Color(red: 0.21, green: 0.27, blue: 0.24)], blur: 25, opacity: 0.7).at(253, -22)
            blob(137, 202, [Color(red: 0.54, green: 0.32, blue: 0.19), Color(red: 0.35, green: 0.20, blue: 0.10)], blur: 20, opacity: 0.7, rotation: -6).at(-51, 289)
            Text("\(c.title.uppercased()) — SCOUT22")
                .font(CarouselFonts.dmMono(8.7)).tracking(2.2)
                .foregroundStyle(gold)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 325, alignment: .leading).at(32, 38)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(3).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.text.lowercased())
                            .font(.system(size: 26, weight: .light)).tracking(0.4)
                            .foregroundStyle(gold)
                            .lineLimit(2).minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sub = row.sub {
                            Text(sub.uppercased())
                                .font(CarouselFonts.dmMono(9.4)).tracking(1.8)
                                .foregroundStyle(dimText)
                        }
                    }
                    .padding(.bottom, 13)
                    Rectangle().fill(gold.opacity(0.35)).frame(height: 1)
                        .padding(.bottom, 13)
                }
            }
            .frame(width: 325, alignment: .leading).at(32, 84)
            bottomLine(c).at(32, 432)
        }
    }

    @ViewBuilder
    private static func bottomLine(_ c: CardInterior) -> some View {
        if let pill = c.pill {
            let label = HStack(spacing: 8) {
                arrow(width: 54)
                Text(pill.uppercased())
                    .font(CarouselFonts.dmMono(9.4)).tracking(1.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(gold)
            if let action = c.pillAction {
                Button(action: action) { label }
            } else {
                label
            }
        }
    }
}

/// Pull one fact out of the priority list by label, for the templates that
/// arrange facts themselves instead of drawing a FactRail.
private func fact(_ facts: [CardFact], _ label: String) -> String? {
    facts.first { $0.label == label }?.value
}

// MARK: - 09 · Boutique serif (after @thewealthcollaborative)

enum BoutiqueSerifCard {
    static let blush = Color(red: 0.97, green: 0.87, blue: 0.87)
    static let maroon = Color(red: 0.42, green: 0.07, blue: 0.13)

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            blush
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.archivoBold(12)).tracking(6)
                .foregroundStyle(maroon)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: designW).at(0, 56)
            VStack(spacing: -4) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line)
                        .font(CarouselFonts.playfairBold(52))
                        .foregroundStyle(maroon)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            // Playfair at 52pt sets on a ~69pt line box, so three title lines
            // run to ~282 — the wordmark below has to start clear of the
            // descenders, not at the nominal block bottom.
            .frame(width: 350).at(20, 84)
            (Text("the ").font(CarouselFonts.playfairItalic(19))
                + Text("SCOUT22 EDIT").font(CarouselFonts.playfairBold(19)))
                .foregroundStyle(maroon)
                .frame(width: designW).at(0, 298)
            Rectangle().fill(maroon.opacity(0.4)).frame(width: 160, height: 1).at(115, 330)
            // The reference's signature: facts ride inside a filled capsule
            // rather than on hairlines.
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7),
                valueFont: CarouselFonts.archivoBoldItalic(13),
                ink: blush,
                width: 290,
                labelInk: blush.opacity(0.7),
                ruleOpacity: 0.3
            )
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(maroon))
            .at(28, 352)
            Text("SWIPE FOR THE ROLE")
                .font(CarouselFonts.archivoBold(10)).tracking(3)
                .foregroundStyle(maroon.opacity(0.65))
                .frame(width: designW).at(0, 436)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            blush
            if let kicker = c.kicker {
                Text(kicker.uppercased())
                    .font(CarouselFonts.dmMono(9)).tracking(2.8)
                    .foregroundStyle(maroon.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: designW).at(0, 34)
            }
            Text(c.title)
                .font(CarouselFonts.playfairBold(34))
                .foregroundStyle(maroon)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 330).at(30, 58)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(maroon.opacity(0.28)).frame(height: 1)
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(i + 1).")
                                .font(CarouselFonts.playfairItalic(15))
                                .foregroundStyle(maroon.opacity(0.65))
                            Text(row.text)
                                .font(CarouselFonts.archivoBold(13.5))
                                .foregroundStyle(maroon)
                                .lineLimit(2).minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(width: 322, alignment: .leading).at(34, 142)
            cta(c).at(80, 424)
        }
    }

    @ViewBuilder
    private static func cta(_ c: CardInterior) -> some View {
        if let pill = c.pill, let action = c.pillAction {
            Button(action: action) {
                Text(pill.uppercased())
                    .font(CarouselFonts.archivoBold(11)).tracking(2.4)
                    .foregroundStyle(blush)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 230, height: 38)
                    .background(Capsule().fill(maroon))
            }
        }
    }
}

// MARK: - 10 · Press clipping (after @hotspotcreatives)

enum PressClippingCard {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let red = Color(red: 0.90, green: 0.14, blue: 0.11)

    static func stamp(_ text: String) -> some View {
        Text(text)
            .font(CarouselFonts.dmMono(8.5)).tracking(1.4)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Rectangle().stroke(ink, lineWidth: 1))
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        let facts = Array(CoverFacts.rail(s, job).prefix(4))
        return ZStack(alignment: .topLeading) {
            paper
            stamp("SCOUT22").at(22, 22)
            stamp("DEADLINE: ONGOING")
                .frame(width: designW - 22, alignment: .trailing).at(0, 22)
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.dmMono(13)).tracking(2.4)
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 346, alignment: .leading).at(22, 74)
            VStack(alignment: .leading, spacing: -2) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    // No condensed face is bundled; a horizontal scale on
                    // Archivo Black stands in. Layout width is unaffected, so
                    // this only ever gains right margin, never overflows.
                    Text(line)
                        .font(CarouselFonts.archivoBlack(40))
                        .foregroundStyle(red)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .scaleEffect(x: 0.88, anchor: .leading)
                }
            }
            .frame(width: 352, alignment: .leading).at(20, 100)
            HStack(spacing: 7) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.label.uppercased())
                            .font(CarouselFonts.dmMono(6.5)).tracking(1.4)
                            .foregroundStyle(ink.opacity(0.55))
                        Text(f.value)
                            .font(CarouselFonts.dmMonoMedium(10))
                            .foregroundStyle(ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(ink, lineWidth: 1))
                }
            }
            .frame(width: 346, alignment: .leading).at(22, 236)
            // First render of cover.hook anywhere — the LLM has written one
            // on every job since v3 and no template ever drew it.
            if let hook = s.hook, !hook.isEmpty {
                Text(hook)
                    .font(CarouselFonts.archivoBold(12.5))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineSpacing(3)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 346, alignment: .leading).at(22, 296)
            }
            Text("↓  SWIPE FOR THE FULL BRIEF")
                .font(CarouselFonts.dmMono(9.5)).tracking(1)
                .foregroundStyle(red).at(22, 442)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            paper
            if let kicker = c.kicker {
                Text(kicker.uppercased())
                    .font(CarouselFonts.dmMono(9)).tracking(2.2)
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 346, alignment: .leading).at(22, 26)
            }
            Text(c.title.uppercased())
                .font(CarouselFonts.archivoBlack(30))
                .foregroundStyle(red)
                .lineLimit(2).minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(x: 0.9, anchor: .leading)
                .frame(width: 352, alignment: .leading).at(20, 50)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(ink).frame(height: 1)
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", i + 1))
                                .font(CarouselFonts.dmMono(10))
                                .foregroundStyle(red)
                                .padding(.top, 2)
                            Text(row.text)
                                .font(CarouselFonts.archivoBold(13))
                                .foregroundStyle(ink)
                                .lineLimit(2).minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(width: 346, alignment: .leading).at(22, 130)
            footer(c).at(22, 442)
        }
    }

    @ViewBuilder
    private static func footer(_ c: CardInterior) -> some View {
        if let pill = c.pill {
            let label = Text("↓  \(pill.uppercased())")
                .font(CarouselFonts.dmMono(9.5)).tracking(1)
                .foregroundStyle(red)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let action = c.pillAction { Button(action: action) { label } } else { label }
        }
    }
}

// MARK: - 11 · Panel plate (after @mahlerprivatestaffing)

enum PanelPlateCard {
    static let panelInk = Color(red: 0.12, green: 0.18, blue: 0.24)

    static var sky: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 0.31, green: 0.55, blue: 0.77), location: 0),
            .init(color: Color(red: 0.56, green: 0.72, blue: 0.85), location: 0.46),
            .init(color: Color(red: 0.78, green: 0.83, blue: 0.85), location: 0.62),
            .init(color: Color(red: 0.54, green: 0.58, blue: 0.61), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    static func tower(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Color(red: 0.49, green: 0.53, blue: 0.58), Color(red: 0.31, green: 0.35, blue: 0.40)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: w, height: h)
            .opacity(0.85)
            .at(x, y)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        let facts = CoverFacts.rail(s, job)
        let tail = [fact(facts, "setup"), fact(facts, "level")].compactMap { $0 }
        return ZStack(alignment: .topLeading) {
            sky
            Ellipse().fill(.white).frame(width: 190, height: 60).blur(radius: 14).opacity(0.75).at(-30, 40)
            Ellipse().fill(.white).frame(width: 170, height: 52).blur(radius: 14).opacity(0.6).at(250, 82)
            tower(288, 270, 38, 218)
            tower(334, 314, 40, 174)
            tower(24, 322, 44, 166)
            tower(78, 296, 32, 192)
            tower(132, 352, 28, 136)
            // The reference stacks role / rule / location / comp inside a
            // translucent plate; the facts are the composition here, so this
            // template arranges them itself instead of drawing a FactRail.
            VStack(spacing: 0) {
                Text((s.role ?? job.title).uppercased())
                    .font(.system(size: 27, weight: .light)).tracking(3.4)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.45)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(.white.opacity(0.55))
                    .frame(width: 56, height: 1).padding(.vertical, 14)
                if let loc = fact(facts, "location") {
                    Text(loc.uppercased())
                        .font(.system(size: 11, weight: .light)).tracking(3)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if let comp = fact(facts, "comp") {
                    Text(comp)
                        .font(.system(size: 17, weight: .light)).tracking(1.6)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 12)
                }
                if !tail.isEmpty {
                    Text(tail.joined(separator: " · ").uppercased())
                        .font(.system(size: 10, weight: .light)).tracking(2.4)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 5)
                }
            }
            .padding(.horizontal, 18)
            .frame(width: 244, height: 236)
            .background(panelInk.opacity(0.84))
            .at(73, 118)
            Text(job.displayCompanyName)
                .font(CarouselFonts.dmMono(10)).tracking(3)
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: designW).at(0, 392)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.37, blue: 0.50), Color(red: 0.13, green: 0.19, blue: 0.24)],
                startPoint: .top, endPoint: .bottom)
            Text(c.title.uppercased())
                .font(.system(size: 28, weight: .light)).tracking(2.6)
                .foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 330, alignment: .leading).at(30, 52)
            Rectangle().fill(.white.opacity(0.5)).frame(width: 56, height: 1).at(30, 132)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.text)
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 13)
                        Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                    }
                }
            }
            .frame(width: 330, alignment: .leading).at(30, 158)
            footer(c).at(0, 438)
        }
    }

    @ViewBuilder
    private static func footer(_ c: CardInterior) -> some View {
        if let pill = c.pill {
            let label = Text(pill.uppercased())
                .font(CarouselFonts.dmMono(9)).tracking(2.8)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: designW)
            if let action = c.pillAction { Button(action: action) { label } } else { label }
        }
    }
}

// MARK: - 12 · Marquee poster (after @bloomsburypulse)

enum MarqueePosterCard {
    static let oxblood = Color(red: 0.36, green: 0.06, blue: 0.08)
    static let gold = Color(red: 0.71, green: 0.64, blue: 0.29)
    static let powder = Color(red: 0.73, green: 0.83, blue: 0.96)
    static let strip = Color(red: 0.95, green: 0.77, blue: 0.85)

    /// Repeating band. The reference runs "NOW HIRING"; we run the company
    /// name, so the ornament carries real data instead of borrowed copy.
    static func marquee(_ text: String, height: CGFloat, size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                Text("\(text) · ")
                    .font(CarouselFonts.archivoBlack(size))
                    .foregroundStyle(gold)
                    .fixedSize()
            }
        }
        .frame(width: designW, height: height, alignment: .leading)
        .background(strip)
        .clipped()
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            oxblood
            marquee(job.displayCompanyName.uppercased(), height: 42, size: 15).at(0, 0)
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.archivoBlack(16)).tracking(3)
                .foregroundStyle(powder)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: designW).at(0, 82)
            VStack(spacing: -6) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line)
                        .font(CarouselFonts.archivoBlack(56))
                        .foregroundStyle(gold)
                        .lineLimit(1).minimumScaleFactor(0.35)
                        .scaleEffect(x: 0.9)
                }
            }
            .frame(width: 366).at(12, 118)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.archivoBlack(7),
                valueFont: CarouselFonts.archivoBlack(14),
                ink: gold,
                width: 346,
                labelInk: powder,
                ruleOpacity: 0.4
            ).at(22, 352)
            HStack {
                Text("SCOUT22")
                Spacer()
                Text("SWIPE →")
            }
            .font(CarouselFonts.archivoBlack(12))
            .foregroundStyle(gold)
            .padding(.horizontal, 16)
            .frame(width: designW, height: 42)
            .background(strip)
            .at(0, 445.5)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            oxblood
            marquee(c.kicker?.uppercased() ?? "SCOUT22", height: 34, size: 12).at(0, 0)
            Text(c.title.uppercased())
                .font(CarouselFonts.archivoBlack(30))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(x: 0.92)
                .frame(width: 358).at(16, 56)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.text.uppercased())
                            .font(CarouselFonts.archivoBlack(14))
                            .foregroundStyle(powder)
                            .lineLimit(2).minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 12)
                        Rectangle().fill(strip.opacity(0.3)).frame(height: 2)
                    }
                }
            }
            .frame(width: 338, alignment: .leading).at(26, 148)
            marquee(c.pill?.uppercased() ?? "SCOUT22", height: 34, size: 12).at(0, 453.5)
        }
    }
}

// MARK: - 13 · Folder tabs (after @hapakristin)

enum FolderTabsCard {
    static let cream = Color(red: 0.99, green: 0.95, blue: 0.89)
    static let sheet = Color(red: 1.00, green: 0.97, blue: 0.93)
    static let hotPink = Color(red: 0.94, green: 0.21, blue: 0.50)
    static let deepPink = Color(red: 0.95, green: 0.42, blue: 0.63)
    static let plum = Color(red: 0.37, green: 0.10, blue: 0.22)
    static let tabFills: [Color] = [
        Color(red: 0.98, green: 0.76, blue: 0.85),
        Color(red: 0.96, green: 0.54, blue: 0.71),
        Color(red: 0.98, green: 0.85, blue: 0.90),
        Color(red: 0.95, green: 0.42, blue: 0.63),
    ]
    static let tabHeights: [CGFloat] = [60, 70, 56, 66]

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        let facts = Array(CoverFacts.rail(s, job).prefix(4))
        return ZStack(alignment: .topLeading) {
            cream
            // The facts *are* the filing system here: one per tab, which is
            // why this template needs no separate rail.
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(facts.enumerated()), id: \.offset) { i, f in
                    VStack(spacing: 3) {
                        Text(f.label.uppercased())
                            .font(CarouselFonts.dmMono(6.5)).tracking(1.4)
                            .foregroundStyle(plum.opacity(0.68))
                        Text(f.value)
                            .font(CarouselFonts.playfairItalic(13))
                            .foregroundStyle(plum)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 6)
                    // Tabs tuck 6pt under the drawer, so the label needs more
                    // bottom padding than the tuck depth or it gets clipped.
                    .padding(.top, 9).padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: tabHeights[i % tabHeights.count], alignment: .bottom)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                            .fill(tabFills[i % tabFills.count])
                    )
                }
            }
            .padding(.horizontal, 14)
            .frame(width: designW, height: 74, alignment: .bottom)
            .at(0, 52)
            Rectangle().fill(sheet).frame(width: designW, height: 367.5).at(0, 120)
            Rectangle().fill(deepPink).frame(width: designW, height: 2).at(0, 120)
            RoundedRectangle(cornerRadius: 13)
                .stroke(hotPink, lineWidth: 4)
                .frame(width: 26, height: 64).at(34, 150)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.98, green: 0.83, blue: 0.88), Color(red: 0.79, green: 0.55, blue: 0.64)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 86, height: 104)
                .overlay(Rectangle().stroke(.white, lineWidth: 5))
                .shadow(color: plum.opacity(0.22), radius: 9, y: 4)
                .rotationEffect(.degrees(4))
                .at(268, 150)
            VStack(alignment: .leading, spacing: -2) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line)
                        .font(CarouselFonts.archivoBlack(38))
                        .foregroundStyle(hotPink)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            .frame(width: 338, alignment: .leading).at(26, 280)
            Text("at \(job.displayCompanyName)")
                .font(CarouselFonts.playfairItalic(17))
                .foregroundStyle(plum)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 338, alignment: .leading).at(26, 414)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            cream
            Text(c.title.lowercased())
                .font(CarouselFonts.playfairItalic(17))
                .foregroundStyle(plum)
                .lineLimit(1).minimumScaleFactor(0.55)
                .padding(.horizontal, 16)
                .frame(width: 210, height: 38)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                        .fill(deepPink)
                )
                .at(26, 44)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8)
                .fill(sheet)
                .frame(width: 338, height: 364)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 8)
                        .stroke(deepPink, lineWidth: 2)
                )
                .at(26, 82)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { i, row in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1).")
                                .font(CarouselFonts.playfairItalic(15))
                                .foregroundStyle(hotPink)
                            Text(row.text)
                                .font(CarouselFonts.archivoBold(13))
                                .foregroundStyle(plum)
                                .lineLimit(2).minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                        Rectangle().fill(hotPink.opacity(0.5)).frame(height: 1)
                    }
                }
            }
            .frame(width: 298, alignment: .leading).at(46, 110)
            footer(c).at(0, 414)
        }
    }

    @ViewBuilder
    private static func footer(_ c: CardInterior) -> some View {
        if let pill = c.pill {
            let label = Text(pill)
                .font(CarouselFonts.dmMono(9)).tracking(2)
                .foregroundStyle(plum.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: designW)
            if let action = c.pillAction { Button(action: action) { label } } else { label }
        }
    }
}

// MARK: - 14 · Motion split (after @onflowsocials)

enum MotionSplitCard {
    static let cream = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let darkInk = Color(red: 0.14, green: 0.13, blue: 0.11)

    static var wall: some View {
        LinearGradient(
            colors: [Color(red: 0.64, green: 0.62, blue: 0.58),
                     Color(red: 0.59, green: 0.57, blue: 0.53),
                     Color(red: 0.54, green: 0.52, blue: 0.49)],
            startPoint: .top, endPoint: .bottom)
    }

    static func cover(_ s: CoverSlide, _ job: JobPostingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            wall
            Rectangle().fill(.white.opacity(0.16)).frame(width: designW, height: 2).at(0, 96)
            Rectangle().fill(.white.opacity(0.16)).frame(width: designW, height: 2).at(0, 302)
            // The blurred figure the reference shoots in motion.
            RoundedRectangle(cornerRadius: 60, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.96, green: 0.92, blue: 0.81), Color(red: 0.78, green: 0.71, blue: 0.54)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 172, height: 334)
                .blur(radius: 25)
                .opacity(0.9)
                .rotationEffect(.degrees(4))
                .at(112, 16)
            // Localised shadow so the cream display type keeps its contrast
            // wherever the blur lands light; the facts flip to dark ink on the
            // bare wall below it.
            RadialGradient(
                colors: [Color(red: 0.15, green: 0.14, blue: 0.11).opacity(0.58), .clear],
                center: .center, startRadius: 10, endRadius: 210
            )
            .frame(width: designW, height: 196).at(0, 150)
            VStack(spacing: -4) {
                ForEach(titleLines(s, job), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 46, weight: .light)).tracking(0.5)
                        .foregroundStyle(cream)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
            }
            .frame(width: 350).at(20, 186)
            FactRail(
                facts: CoverFacts.rail(s, job),
                labelFont: CarouselFonts.dmMono(7.5),
                valueFont: .system(size: 15, weight: .regular),
                ink: darkInk,
                labelInk: darkInk.opacity(0.58),
                ruleOpacity: 0.3
            ).at(18, 378)
            Text(job.displayCompanyName.uppercased())
                .font(CarouselFonts.dmMono(9.5)).tracking(3.4)
                .foregroundStyle(darkInk)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: designW).at(0, 444)
        }
    }

    static func interior(_ c: CardInterior) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.14, green: 0.13, blue: 0.11)
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.37, green: 0.35, blue: 0.29), Color(red: 0.17, green: 0.16, blue: 0.13)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 230, height: 330)
                .blur(radius: 30)
                .opacity(0.85)
                .rotationEffect(.degrees(-8))
                .at(180, 190)
            Text("\(c.title):")
                .font(CarouselFonts.playfairItalic(30))
                .foregroundStyle(cream)
                .lineLimit(2).minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 334, alignment: .leading).at(28, 46)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 11) {
                        Circle().fill(cream).frame(width: 5, height: 5).padding(.top, 8)
                        Text(row.text)
                            .font(.system(size: 15.5, weight: .light))
                            .foregroundStyle(cream)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 322, alignment: .leading).at(34, 132)
            footer(c).at(28, 440)
        }
    }

    @ViewBuilder
    private static func footer(_ c: CardInterior) -> some View {
        if let pill = c.pill {
            let label = Text(pill.uppercased())
                .font(CarouselFonts.dmMono(9)).tracking(2.4)
                .foregroundStyle(cream.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.6)
            if let action = c.pillAction { Button(action: action) { label } } else { label }
        }
    }
}

// Mini first-slide preview for grid tiles (Saved / Applications) — the
// job's actual cover instead of a placeholder. Renders through CardCanvas,
// which self-scales to the tile width. Hit-testing off so the tile's button
// wins.
struct JobCardPreview: View {
    let job: JobPostingRecord
    let carousel: Carousel

    static func canPreview(job: JobPostingRecord, carousel: Carousel) -> Bool {
        !carousel.renderableSlides.isEmpty
    }

    var body: some View {
        if let slide = carousel.renderableSlides.first {
            CardTemplateSlideView(
                slide: slide,
                style: CarouselStyle.resolve(companyKey: job.carouselCompanyKey, themeID: carousel.themeId),
                job: job,
                onEmailFounder: nil,
                previewMode: true
            )
            .allowsHitTesting(false)
        }
    }
}
