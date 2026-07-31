import SwiftUI

// CarouselFeedCard renders one ATS job as a vertical-feed card whose interior
// is a horizontal pager of structured slides. The slides come from the
// generate-carousel edge function (cover, about_company, role, requirements,
// details). Visuals are resolved client-side: `carousel.theme_id` gives the
// palette family, and CarouselStyle picks a per-job layout archetype
// (full-bleed archetypes plus 4:5 card templates) so the feed reads like
// a mixed Instagram timeline instead of one recolored template.
// Covers live in CarouselCovers.swift; interior slides share the
// parameterized layouts below.

private let slideAutoAdvanceSeconds: TimeInterval = 3.0

// TODO(deferred): snapshot/UI test coverage for this feed card (and the
// FounderEmailSheet compose flow). Needs an external snapshot lib
// (swift-snapshot-testing via SPM) + baseline images; the Scout22Tests target
// is the foundation to add it onto. Effort: medium. See docs/DEFERRED_WORK.md.
struct CarouselFeedCard: View {
    let job: JobPostingRecord
    let carousel: Carousel
    let safeAreaBottom: CGFloat
    let isActive: Bool
    let onApply: () -> Void
    let onEmailFounder: (() -> Void)?
    let onSave: () -> Void
    let isSaved: Bool

    @State private var currentIndex: Int = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    private var style: CarouselStyle {
        CarouselStyle.resolve(jobID: job.id, themeID: carousel.themeId)
    }

    private var theme: CarouselTheme { style.theme }

    private var slides: [CarouselSlide] {
        carousel.renderableSlides.filter { slide in
            // The backend always emits a details slide (3-slide minimum).
            // When neither the slide nor the job has location/type/comp/perks
            // it would render as a bare "the deets" header — drop it rather
            // than end the carousel on an empty card.
            guard case .details(let details) = slide else { return true }
            return details.hasRenderableContent(for: job)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                theme.backgroundGradient.ignoresSafeArea()

                TabView(selection: $currentIndex) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        SlideView(slide: slide, style: style, job: job, onEmailFounder: onEmailFounder)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                bottomControls
            }
        }
        .onAppear { restartAutoAdvanceIfActive() }
        .onDisappear { cancelAutoAdvance() }
        .onChange(of: isActive) { _, _ in restartAutoAdvanceIfActive() }
        .onChange(of: currentIndex) { _, _ in restartAutoAdvanceIfActive() }
    }

    // MARK: - Auto-advance

    private func restartAutoAdvanceIfActive() {
        cancelAutoAdvance()
        guard isActive, slides.count > 1 else { return }
        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(slideAutoAdvanceSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    currentIndex = (currentIndex + 1) % slides.count
                }
            }
        }
    }

    private func cancelAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    // MARK: - Bottom overlay

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    progressBar

                    HStack(alignment: .bottom, spacing: 14) {
                        // Left: full-width Apply pill (mirrors JobFeedCard for reels,
                        // but the action opens the WebView drawer instead of email),
                        // with the founder-intro pill as the secondary path.
                        VStack(spacing: 8) {
                            Button(action: onApply) {
                                Text(job.canApplyViaDrawer ? "Apply Now" : "Apply Unavailable")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(job.canApplyViaDrawer ? PassportTheme.accent : Color.white.opacity(0.15))
                                    .foregroundStyle(job.canApplyViaDrawer ? .black : .white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(!job.canApplyViaDrawer)

                            if let onEmailFounder {
                                Button(action: onEmailFounder) {
                                    Label("Pitch the founder", systemImage: "paperplane.fill")
                                        .font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.12))
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Right: action column matching reel cards.
                        VStack(spacing: 18) {
                            FeedActionButton(
                                symbol: isSaved ? "bookmark.fill" : "bookmark",
                                isActive: isSaved,
                                label: "Save",
                                action: onSave
                            )
                            if let shareURL = ShareConfig.shareURL(forJobID: job.id) {
                                FeedShareButton(url: shareURL)
                            }
                        }
                        .frame(width: 56)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, safeAreaBottom + FeedLayout.cardBottomClearance)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(i <= currentIndex ? Color.white : Color.white.opacity(0.30))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: currentIndex)
            }
        }
    }
}

// MARK: - Slide router

private struct SlideView: View {
    let slide: CarouselSlide
    let style: CarouselStyle
    let job: JobPostingRecord
    let onEmailFounder: (() -> Void)?

    var body: some View {
        // 4:5 card templates render every slide type through their own
        // renderer (CarouselCardTemplates.swift) — card on a dark ground,
        // the way the reference IG posts sit in the feed.
        if style.archetype.isCardTemplate {
            CardTemplateSlideView(slide: slide, style: style, job: job, onEmailFounder: onEmailFounder)
        } else {
            fullBleed
        }
    }

    @ViewBuilder
    private var fullBleed: some View {
        switch slide {
        case .cover(let s):         cover(s)
        case .aboutCompany(let s):  AboutCompanySlideView(slide: s, style: style)
        case .role(let s):          BulletSlideView(title: "what you'd actually do", bullets: s.bullets, style: style)
        case .requirements(let s):  BulletSlideView(title: "you're a fit if", bullets: s.bullets, style: style)
        case .perks(let s):         BulletSlideView(title: "the good stuff", bullets: s.bullets, style: style)
        case .founder(let s):       FounderSlideView(slide: s, style: style, onPitch: onEmailFounder)
        case .details(let s):       DetailsSlideView(slide: s, style: style, job: job)
        // Filtered out of `slides` before we get here; render nothing if one
        // ever reaches this view.
        case .unknown:              EmptyView()
        }
    }

    // Covers are fully custom per archetype (CarouselCovers.swift). Card
    // templates never reach here; the default satisfies exhaustiveness.
    @ViewBuilder
    private func cover(_ s: CoverSlide) -> some View {
        switch style.archetype {
        case .notification: NotificationCoverView(slide: s, style: style, job: job)
        case .glitchWindow: GlitchWindowCoverView(slide: s, style: style, job: job)
        case .chromeStar:   ChromeStarCoverView(slide: s, style: style, job: job)
        case .liquidChrome: LiquidChromeCoverView(slide: s, style: style, job: job)
        default:            EmptyView()
        }
    }
}

// MARK: - Interior slide chrome

// Shared interior scaffold: vertical placement, bottom clearance, and the
// per-archetype container — neonCard and notification wrap their content in
// a card, everything else renders full-bleed.
private struct SlideScaffold<Content: View>: View {
    let style: CarouselStyle
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 60)
            container
            Spacer(minLength: 0)
        }
        .padding(.horizontal, style.usesInteriorCard ? 20 : 28)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var container: some View {
        switch style.archetype {
        case .notification:
            inner
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(style.theme.surface)
                )
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
                .rotationEffect(.degrees(-0.6))
        case .glitchWindow:
            inner
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style.theme.accent.opacity(0.9), lineWidth: 1.5)
                )
        case .chromeStar:
            inner
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(style.theme.surface)
                )
                .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        case .liquidChrome:
            inner
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidChromeCardBackground())
        default:
            inner
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 22) { content() }
    }
}

// Section header ("the backstory", "the deets", …) in the archetype's voice:
// glitch gets a prompt chevron, the rest type only.
private struct SlideHeader: View {
    let title: String
    let style: CarouselStyle

    var body: some View {
        switch style.archetype {
        case .glitchWindow:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(">")
                    .font(style.headerFont)
                    .foregroundStyle(style.theme.accent)
                Text(style.headerText(title))
                    .font(style.headerFont)
                    .foregroundStyle(style.headerColor)
            }
        default:
            Text(style.headerText(title))
                .font(style.headerFont)
                .foregroundStyle(style.headerColor)
        }
    }
}

// MARK: - Individual slide layouts

// Wrapping chip row — chips flow onto the next line when they don't fit,
// so a long location plus a salary range never overflows the slide.
// Internal: archetype covers in CarouselCovers.swift reuse it.
struct FlowChips: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center:   x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default:        x = bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let widthIfAdded = current.width + (current.indices.isEmpty ? 0 : spacing) + size.width
            if !current.indices.isEmpty && widthIfAdded > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private struct AboutCompanySlideView: View {
    let slide: AboutCompanySlide
    let style: CarouselStyle

    private var theme: CarouselTheme { style.theme }

    var body: some View {
        SlideScaffold(style: style) {
            Text(style.headerText("the backstory"))
                .font(kickerFont)
                .tracking(2)
                .foregroundStyle(theme.textSecondary)

            if let company = slide.company {
                SlideHeader(title: company, style: style)
            }

            if let blurb = slide.blurb {
                Text(blurb)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let industry = slide.industry {
                    factRow(icon: "tag.fill", label: industry)
                }
                if let stage = slide.stage {
                    factRow(icon: "chart.line.uptrend.xyaxis", label: stage.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                if let backed = slide.backedBy {
                    factRow(icon: "sparkles", label: "Backed by \(backed)")
                }
            }
            .padding(.top, 6)
        }
    }

    private var kickerFont: Font {
        switch style.archetype {
        case .notification:              return .system(size: 13, weight: .semibold)
        case .glitchWindow:              return .system(size: 12, weight: .bold, design: .monospaced)
        case .chromeStar, .liquidChrome: return .system(size: 13, weight: .semibold, design: .serif)
        default:                         return .system(size: 14, weight: .heavy, design: .rounded)
        }
    }

    private func factRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

private struct BulletSlideView: View {
    let title: String
    let bullets: [String]
    let style: CarouselStyle

    @State private var revealed = false

    private var theme: CarouselTheme { style.theme }

    var body: some View {
        SlideScaffold(style: style) {
            SlideHeader(title: title, style: style)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                    bulletRow(index: index, text: bullet)
                        // F1: bullets cascade in as the slide appears.
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 14)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8)
                                .delay(Double(index) * 0.08),
                            value: revealed
                        )
                }
            }
        }
        .onAppear { revealed = true }
        .onDisappear { revealed = false }
    }

    // Bullet treatment in the archetype's voice: neon chevrons, notification
    // dots — the default keeps the SF-symbol glyph rows.
    @ViewBuilder
    private func bulletRow(index: Int, text: String) -> some View {
        switch style.archetype {
        case .notification:
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
                Text(text)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: theme.bulletGlyph)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 4)
                Text(text)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// F7: "meet the founder" — the person a pitch actually reaches. CTA wires
// to the same founder-pitch flow as the feed pill (nil for big-cos, where
// the backend also skips emitting this slide).
private struct FounderSlideView: View {
    let slide: FounderSlide
    let style: CarouselStyle
    let onPitch: (() -> Void)?

    private var theme: CarouselTheme { style.theme }

    private var firstName: String {
        slide.name?.split(separator: " ").first.map(String.init) ?? "the founder"
    }

    var body: some View {
        SlideScaffold(style: style) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.2))
                    .frame(width: 84, height: 84)
                Text(String(firstName.prefix(1)).uppercased())
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(theme.accent)
            }

            Text(style.headerText("meet \(firstName) 👋"))
                .font(style.headerFont)
                .foregroundStyle(style.headerColor)

            if let name = slide.name {
                Text([name, slide.roleTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
            }

            Text("your pitch lands in their inbox — not an ATS black hole.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let onPitch {
                Button(action: onPitch) {
                    Label("Pitch \(firstName)", systemImage: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(theme.accent)
                        .foregroundStyle(style.onAccent)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct DetailsSlideView: View {
    let slide: DetailsSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    var body: some View {
        SlideScaffold(style: style) {
            SlideHeader(title: "the deets", style: style)

            VStack(alignment: .leading, spacing: 14) {
                if let loc = slide.location ?? job.location {
                    detailRow(icon: "mappin.and.ellipse", label: "Location", value: loc)
                }
                if let emp = slide.employment ?? job.employmentType?.title {
                    detailRow(icon: "briefcase.fill", label: "Type", value: emp)
                }
                if let comp = slide.compensation ?? job.compensationText {
                    detailRow(icon: "dollarsign.circle.fill", label: "Compensation", value: comp)
                }
            }

            if let perks = slide.perks, !perks.isEmpty {
                Text("Perks")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(perks.enumerated()), id: \.offset) { _, perk in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.accent)
                            Text(perk)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textPrimary.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(theme.textSecondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }
}

// MARK: - DetailsSlide helpers

extension DetailsSlide {
    /// Whether DetailsSlideView would have at least one row to draw, given
    /// its job-field fallbacks. Mirrors that view's row conditions; empty
    /// strings count as missing.
    func hasRenderableContent(for job: JobPostingRecord) -> Bool {
        if let loc = location ?? job.location, !loc.isEmpty { return true }
        if let emp = employment ?? job.employmentType?.title, !emp.isEmpty { return true }
        if let comp = compensation ?? job.compensationText, !comp.isEmpty { return true }
        if let perks, !perks.isEmpty { return true }
        return false
    }
}

// MARK: - JobPostingRecord helpers

extension JobPostingRecord {
    var canApplyViaDrawer: Bool {
        applyUrl != nil && !(applyUrl?.isEmpty ?? true)
    }

    var canApply: Bool {
        !applicationEmail.isEmpty || canApplyViaDrawer
    }

    var displayCompanyName: String {
        if let name = company?.name, !name.isEmpty { return name }
        return companyName
    }

    var displayCompanyLogoURL: URL? {
        guard let raw = company?.logoUrl, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var sourceBadge: SourceBadgeStyle? {
        switch sourceKind {
        case .ats, .board:   return .pitch
        case .reel:          return nil
        case .employerPost:  return nil
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Source badge

enum SourceBadgeStyle {
    case pitch

    var label: String {
        switch self {
        case .pitch: return "PORTFOLIO"
        }
    }

    var background: Color {
        switch self {
        case .pitch: return Color(red: 0.10, green: 0.45, blue: 0.95)
        }
    }
}

struct SourceBadgeView: View {
    let style: SourceBadgeStyle

    var body: some View {
        Text(style.label)
            .font(.caption2.weight(.heavy))
            .tracking(1.0)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(style.background)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

// F1: gentle pulsing "swipe →" affordance on the cover slide.
// Internal: archetype covers in CarouselCovers.swift reuse it.
struct SwipeHint: View {
    let theme: CarouselTheme
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Text("swipe")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(theme.textSecondary.opacity(pulse ? 0.9 : 0.45))
        .offset(x: pulse ? 4 : 0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}
