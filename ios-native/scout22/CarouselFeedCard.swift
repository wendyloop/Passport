import SwiftUI

// CarouselFeedCard renders one ATS job as a vertical-feed card whose interior
// is a horizontal pager of structured slides. The slides come from the
// generate-carousel edge function (cover, about_company, role, requirements,
// perks, founder, details). Visuals are resolved client-side: CarouselStyle
// picks a per-job layout archetype so the feed reads like a mixed Instagram
// timeline instead of one recolored template.
//
// Every archetype is a 4:5 card template drawn on a dark ground — the way the
// reference IG posts sit in a feed. Layouts live in CarouselCardTemplates.swift;
// this file owns the pager, the apply/pitch controls, and the feed chrome.

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
    /// Admin-only: render this job's cards and drop them in Photos. nil for
    /// everyone else, which is what keeps the control off a normal feed.
    var onSaveCards: (() -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    private var style: CarouselStyle {
        CarouselStyle.resolve(companyKey: job.carouselCompanyKey, themeID: carousel.themeId)
    }

    private var theme: CarouselTheme { style.theme }

    private var slides: [CarouselSlide] {
        carousel.renderableSlides.filter { slide in
            // The founder slide is the in-carousel twin of the "Pitch the
            // founder" pill, so it follows the same switch. With the pill
            // hidden it would be a card introducing someone you can't
            // contact — a dead end with a stranger's name on it. Flipping
            // FounderPitchUI.isEnabled back on restores both together; the
            // backend keeps emitting the slide either way, so nothing needs
            // regenerating.
            if case .founder = slide {
                return FounderPitchUI.isEnabled && job.founderPitchAllowed
            }
            // The backend always emits a details slide (3-slide minimum).
            // When neither the slide nor the job has location/type/comp
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
                        CardTemplateSlideView(
                            slide: slide,
                            style: style,
                            job: job,
                            onEmailFounder: onEmailFounder
                        )
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
                            if let onSaveCards {
                                FeedActionButton(
                                    symbol: "square.and.arrow.down",
                                    isActive: false,
                                    label: "Cards",
                                    action: onSaveCards
                                )
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

// MARK: - DetailsSlide helpers

extension DetailsSlide {
    /// Whether the details card would have at least one row to draw, given
    /// its job-field fallbacks. Mirrors `CardTemplateSlideView.detailRows`;
    /// empty strings count as missing.
    func hasRenderableContent(for job: JobPostingRecord) -> Bool {
        if let loc = location ?? job.location, !loc.isEmpty { return true }
        if let emp = employment ?? job.employmentType?.title, !emp.isEmpty { return true }
        if let comp = compensation ?? job.compensationText, !comp.isEmpty { return true }
        return false
    }
}

// MARK: - JobPostingRecord helpers

extension JobPostingRecord {
    /// Key the carousel template is chosen from — every role at one employer
    /// resolves to the same look. Prefers the FK, then the embedded company
    /// row, then the denormalised name so reel/employer rows (which carry no
    /// company_id) still group instead of scattering per job.
    var carouselCompanyKey: String {
        if let id = companyID, !id.isEmpty { return id }
        if let id = company?.id, !id.isEmpty { return id }
        return displayCompanyName
    }

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
