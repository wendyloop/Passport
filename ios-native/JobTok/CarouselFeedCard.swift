import SwiftUI

// CarouselFeedCard renders one ATS job as a vertical-feed card whose interior
// is a horizontal pager of structured slides. The slides come from the
// generate-carousel edge function (cover, about_company, role, requirements,
// details). Theme is resolved client-side from `carousel.theme_id`.

private let slideAutoAdvanceSeconds: TimeInterval = 3.0

// TODO(deferred): snapshot/UI test coverage for this feed card (and the
// FounderEmailSheet compose flow). Needs an external snapshot lib
// (swift-snapshot-testing via SPM) + baseline images; the JobTokTests target
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

    private var theme: CarouselTheme { CarouselTheme.resolve(carousel.themeId) }

    private var slides: [CarouselSlide] {
        carousel.renderableSlides
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                theme.backgroundGradient.ignoresSafeArea()

                TabView(selection: $currentIndex) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        SlideView(slide: slide, theme: theme, job: job)
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
    let theme: CarouselTheme
    let job: JobPostingRecord

    var body: some View {
        switch slide {
        case .cover(let s):         CoverSlideView(slide: s, theme: theme, job: job)
        case .aboutCompany(let s):  AboutCompanySlideView(slide: s, theme: theme)
        case .role(let s):          BulletSlideView(title: "what you'd actually do", bullets: s.bullets, theme: theme)
        case .requirements(let s):  BulletSlideView(title: "you're a fit if", bullets: s.bullets, theme: theme)
        case .perks(let s):         BulletSlideView(title: "the good stuff", bullets: s.bullets, theme: theme)
        case .details(let s):       DetailsSlideView(slide: s, theme: theme, job: job)
        // Filtered out of `slides` before we get here; render nothing if one
        // ever reaches this view.
        case .unknown:              EmptyView()
        }
    }
}

// MARK: - Individual slide layouts

// TODO(deferred): Feature backlog C — social visual language: sticker
// chips with rotation, caption-highlight text blocks, doodle accents,
// cascade-in bullets, "swipe →" affordance, founder slide with email CTA.
// See docs/DEFERRED_WORK.md (Feature backlog).
// Fact-first cover: job title is the headline; company, location, and pay
// are scannable chips. No tagline — candidates decide from facts in under a
// second, TikTok-speed. Two layouts alternate deterministically per job so
// the feed doesn't feel stamped from one template.
private struct CoverSlideView: View {
    let slide: CoverSlide
    let theme: CarouselTheme
    let job: JobPostingRecord

    private var centeredLayout: Bool {
        // Stable per job — the same job always gets the same layout.
        job.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 2 == 1
    }

    private var title: String {
        slide.role ?? job.title
    }

    private var companyName: String? {
        slide.company ?? job.displayCompanyName.nonEmpty
    }

    private var compensation: String? {
        slide.compensation ?? job.compensationSummary ?? job.compensationText
    }

    var body: some View {
        VStack(alignment: centeredLayout ? .center : .leading, spacing: 20) {
            Spacer(minLength: 60)

            if let logo = job.displayCompanyLogoURL {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        EmptyView()
                    }
                }
                .frame(width: centeredLayout ? 84 : 72, height: centeredLayout ? 84 : 72)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let company = companyName {
                Text(company.uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(theme.textSecondary)
            }

            Text(title)
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(centeredLayout ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            // The 90%-signal: one concrete line about what you'd actually do.
            if let youd = slide.youdLine, !youd.isEmpty {
                Text(youd)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary.opacity(0.85))
                    .multilineTextAlignment(centeredLayout ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            factChips
                .padding(.top, 2)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: centeredLayout ? .center : .leading)
    }

    private var factChips: some View {
        // Order = decision weight from job-seeker research: salary first
        // (89% call it the most helpful element), then experience fit,
        // work mode, location, freshness.
        FlowChips(alignment: centeredLayout ? .center : .leading) {
            if let comp = compensation, !comp.isEmpty {
                coverChip(icon: "dollarsign.circle.fill", text: comp)
            }
            if let exp = slide.experience, !exp.isEmpty {
                coverChip(icon: "chart.bar.fill", text: experienceLabel(exp))
            }
            if let mode = slide.workMode, !mode.isEmpty {
                coverChip(icon: "house.fill", text: mode)
            }
            if let loc = slide.location ?? job.location, !loc.isEmpty {
                coverChip(icon: "mappin.and.ellipse", text: loc)
            }
            if let type = job.employmentType?.title {
                coverChip(icon: "briefcase.fill", text: type)
            }
            coverChip(icon: "clock.fill", text: SharedFormatters.relativeAge(of: job.createdAt))
        }
    }

    private func experienceLabel(_ raw: String) -> String {
        switch raw {
        case "intern": return "internship"
        case "entry": return "0-2 yrs"
        case "mid": return "2-5 yrs"
        case "senior": return "senior"
        case "staff": return "staff+"
        case "exec": return "leadership"
        default: return raw
        }
    }

    private func coverChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.accent.opacity(0.16))
        .foregroundStyle(theme.accent)
        .clipShape(Capsule())
    }
}

// Wrapping chip row — chips flow onto the next line when they don't fit,
// so a long location plus a salary range never overflows the slide.
private struct FlowChips: Layout {
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
    let theme: CarouselTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 60)

            Text("the backstory")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(theme.textSecondary)

            if let company = slide.company {
                Text(company)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
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

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let theme: CarouselTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 60)

            Text(title)
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: theme.bulletGlyph)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 22, alignment: .center)
                            .padding(.top, 4)
                        Text(bullet)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailsSlideView: View {
    let slide: DetailsSlide
    let theme: CarouselTheme
    let job: JobPostingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 60)

            Text("the deets")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)

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

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
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
