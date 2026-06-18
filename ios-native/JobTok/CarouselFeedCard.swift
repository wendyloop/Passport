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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
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
            VStack(alignment: .leading, spacing: 4) {
                let genericNames: Set<String> = ["unknown", "tiktok", "instagram"]
                if !job.companyName.isEmpty && !genericNames.contains(job.companyName.lowercased()) {
                    Text(job.companyName)
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
}

// MARK: - JobPostingRecord carousel helpers

extension JobPostingRecord {
    var canApplyViaDrawer: Bool {
        applyUrl != nil && !(applyUrl?.isEmpty ?? true)
    }

    var canApply: Bool {
        !applicationEmail.isEmpty || canApplyViaDrawer
    }
}
