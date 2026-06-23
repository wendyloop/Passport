import SwiftUI

// MARK: - CarouselFeedCard
// Displays a job posting as a horizontal paging scroll of generated slide images.
// Used when job.carouselSlideUrls is non-empty (carousel-service generated slides).

struct CarouselFeedCard: View {
    let job: JobPostingRecord
    let safeAreaBottom: CGFloat
    let onApply: () -> Void
    let onSave: () -> Void
    let isSaved: Bool

    @State private var currentPage = 0

    private var hasSlides: Bool {
        !(job.carouselSlideUrls ?? []).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if hasSlides {
                    // Slide pager
                    TabView(selection: $currentPage) {
                        ForEach(Array((job.carouselSlideUrls ?? []).enumerated()), id: \.offset) { index, urlString in
                            AsyncImage(url: URL(string: urlString)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Rectangle()
                                        .fill(Color(white: 0.12))
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.tertiary)
                                        )
                                case .empty:
                                    Rectangle()
                                        .fill(Color(white: 0.08))
                                        .overlay(ProgressView().tint(.white))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                } else {
                    // ATS rows arrive without generated slides. Render a dark
                    // company splash so the card still has visual presence.
                    companySplash(width: proxy.size.width, height: proxy.size.height)
                }

                // Gradient + controls overlay
                VStack(spacing: 0) {
                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 260)
                    .overlay(alignment: .bottom) {
                        bottomControls(proxy: proxy)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bottomControls(proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Dot indicators
            if let slides = job.carouselSlideUrls, slides.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.white : Color.white.opacity(0.35))
                            .frame(width: i == currentPage ? 8 : 6, height: i == currentPage ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Job info
            VStack(alignment: .leading, spacing: 6) {
                if let badge = job.sourceBadge {
                    SourceBadgeView(style: badge)
                }

                if !job.title.isEmpty {
                    Text(job.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                }

                let displayName = job.displayCompanyName
                let genericNames: Set<String> = ["unknown", "tiktok", "instagram"]
                if !displayName.isEmpty && !genericNames.contains(displayName.lowercased()) {
                    Text(displayName)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    if let fn = job.jobFunction {
                        Text(fn.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let loc = job.location, !loc.isEmpty {
                        if job.jobFunction != nil {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Text(loc)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 12) {
                if job.canApply {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(PassportTheme.accent)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, safeAreaBottom + 20)
        }
    }

    @ViewBuilder
    private func companySplash(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.18), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let logoURL = job.displayCompanyLogoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .padding(48)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    default:
                        companyMonogram
                    }
                }
            } else {
                companyMonogram
            }
        }
        .frame(width: width, height: height)
    }

    private var companyMonogram: some View {
        Text(initials(for: job.displayCompanyName))
            .font(.system(size: 96, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .padding(40)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let chars = words.compactMap { $0.first }
        return chars.isEmpty ? "•" : String(chars).uppercased()
    }
}

// MARK: - JobPostingRecord carousel helpers

extension JobPostingRecord {
    var canApplyViaDrawer: Bool {
        applyUrl != nil && !(applyUrl?.isEmpty ?? true)
    }

    var canApply: Bool {
        !applicationEmail.isEmpty || canApplyViaDrawer
    }

    // Use the joined companies row when available; fall back to the denormalized
    // company_name column. ATS rows always carry an embedded company; reels and
    // employer posts use the legacy column.
    var displayCompanyName: String {
        if let name = company?.name, !name.isEmpty { return name }
        return companyName
    }

    var displayCompanyLogoURL: URL? {
        guard let raw = company?.logoUrl, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    // Drives the small badge in the feed card. ATS rows are the only ones that
    // need an explicit marker today; reels + employer posts share the default
    // "live JobTok video" look so we keep the badge off.
    var sourceBadge: SourceBadgeStyle? {
        switch sourceKind {
        case .ats:           return .pitch
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
