import SwiftUI

// Archetype cover slides. Each archetype gets a fully custom cover — the
// first slide is what sells the scroll-stop — while interior slides share
// parameterized layouts in CarouselFeedCard.swift. All covers render the
// same underlying facts (CoverFacts) in their own visual language, use a
// letter monogram instead of the remote logo (deterministic, no network),
// and keep content above FeedLayout.slideContentClearance so the apply
// controls never overlap.

// MARK: - Editorial (newspaper front page)

struct EditorialCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    private var companyName: String {
        slide.company ?? job.displayCompanyName
    }

    private var year: String {
        String(Calendar.current.component(.year, from: job.createdAt))
    }

    // Newsprint body rows under the headline: hook + you'd-line + top facts,
    // capped so long JDs can't push the barcode off the page.
    private var deckLines: [String] {
        var lines: [String] = []
        if let hook = slide.hook, !hook.isEmpty { lines.append(hook) }
        if let youd = slide.youdLine, !youd.isEmpty { lines.append(youd) }
        lines.append(contentsOf: CoverFacts.build(slide: slide, job: job).prefix(3).map(\.text))
        return Array(lines.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 40)

            masthead

            Text("NOW HIRING")
                .font(.system(size: 11, weight: .heavy, design: .serif))
                .tracking(1.5)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.top, 6)

            Text(slide.role ?? job.title)
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(deckLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("↳")
                            .font(theme.bodyFont.weight(.bold))
                            .foregroundStyle(theme.accent)
                        Text(line)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                SwipeHint(theme: theme)
                Spacer()
                BarcodeMotif(seed: job.id, color: theme.textPrimary)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var masthead: some View {
        VStack(spacing: 8) {
            Rectangle().fill(theme.textPrimary).frame(height: 3)
            Text(companyName.uppercased())
                .font(.system(size: 38, weight: .black, design: .serif))
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
            Rectangle().fill(theme.textPrimary.opacity(0.5)).frame(height: 0.8)
            HStack {
                Text("ISSUE 01")
                Spacer()
                Text("HIRING EDITION")
                Spacer()
                Text(year)
            }
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .tracking(1.5)
            .foregroundStyle(theme.textSecondary)
            Rectangle().fill(theme.textPrimary.opacity(0.5)).frame(height: 0.8)
        }
    }
}

// MARK: - Neon card (dark, glowing border)

struct NeonCardCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    var body: some View {
        VStack {
            Spacer(minLength: 60)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    CompanyMonogram(
                        name: slide.company ?? job.displayCompanyName,
                        background: theme.accent,
                        foreground: style.onAccent,
                        size: 38
                    )
                    Text("\(slide.company ?? job.displayCompanyName) is hiring")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }

                Text(slide.role ?? job.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let youd = slide.youdLine, !youd.isEmpty {
                    Text(youd)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FlowChips(alignment: .leading) {
                    ForEach(CoverFacts.build(slide: slide, job: job).prefix(4)) { fact in
                        Text(fact.text)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(theme.accent)
                            .background(theme.accent.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 1))
                    }
                }

                // Decorative pager dots — part of the illustration, distinct
                // from the real progress bar in the bottom controls.
                HStack(spacing: 5) {
                    Capsule().fill(theme.accent).frame(width: 16, height: 5)
                    Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
                    Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(theme.accent.opacity(0.85), lineWidth: 1.5)
            )
            .shadow(color: theme.accent.opacity(0.45), radius: 18)

            Spacer()

            SwipeHint(theme: theme)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, FeedLayout.slideContentClearance)
    }
}

// MARK: - Notification (illustrated push on a pastel wallpaper)

// Deliberately illustrative, not a system-UI replica: cards are rotated,
// corners oversized, timestamps are the word "now", and there is no status
// bar or clock (App Review 2.3.x caution).
struct NotificationCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    private var companyName: String {
        slide.company ?? job.displayCompanyName
    }

    private var factLine: String? {
        let texts = CoverFacts.build(slide: slide, job: job).prefix(3).map(\.text)
        return texts.isEmpty ? nil : texts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 90)

            ZStack {
                // A second card peeking out behind sells the "stack".
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.45))
                    .frame(height: 58)
                    .padding(.horizontal, 26)
                    .offset(y: -16)
                    .rotationEffect(.degrees(0.8))

                notificationCard
                    .rotationEffect(.degrees(-1.5))
            }

            if let factLine {
                Text(factLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.7))
                    .clipShape(Capsule())
                    .rotationEffect(.degrees(0.8))
            }

            Spacer()

            HStack(spacing: 6) {
                Text("swipe to see more")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity)
    }

    private var notificationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanyMonogram(
                name: companyName,
                background: theme.textPrimary,
                foreground: .white,
                size: 42,
                cornerRadius: 12
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(companyName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("now")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                }
                (Text("is hiring you for ")
                    + Text(slide.role ?? job.title).bold()
                    + Text(" — tap to apply"))
                    .font(.system(size: 15))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Scrapbook (cream paper, stickers, glyph accents)

struct ScrapbookCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 50)

            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    CompanyMonogram(
                        name: slide.company ?? job.displayCompanyName,
                        background: theme.accent,
                        foreground: style.onAccent,
                        size: 36
                    )
                    Text("\(slide.company ?? job.displayCompanyName) is hiring")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(style.scrapbookDecor)
                    .font(.system(size: 36))
                    .rotationEffect(.degrees(10))
            }

            Text(slide.role ?? job.title)
                .font(theme.titleFont)
                .foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)

            if let youd = slide.youdLine, !youd.isEmpty {
                Text(youd)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                    .rotationEffect(.degrees(-1.5))
            }

            FlowChips(alignment: .leading) {
                ForEach(Array(CoverFacts.build(slide: slide, job: job).enumerated()), id: \.element.id) { index, fact in
                    stickerChip(fact, index: index)
                }
            }

            Spacer()

            HStack(alignment: .bottom) {
                HStack(spacing: 5) {
                    Capsule().fill(theme.accent).frame(width: 16, height: 5)
                    Circle().fill(theme.accent.opacity(0.3)).frame(width: 5, height: 5)
                    Circle().fill(theme.accent.opacity(0.3)).frame(width: 5, height: 5)
                }
                Spacer()
                SwipeHint(theme: theme)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, FeedLayout.slideContentClearance)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stickerChip(_ fact: CoverFact, index: Int) -> some View {
        // Alternate the wobble so neighboring stickers tilt apart.
        let wobble = Double(index % 3) - 1.0
        return HStack(spacing: 6) {
            Image(systemName: fact.icon)
                .font(.system(size: 12, weight: .bold))
            Text(fact.text)
                .font(.system(size: 14, weight: .bold, design: .serif))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .foregroundStyle(theme.accent)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        .rotationEffect(.degrees(wobble * 1.6))
    }
}

// MARK: - Shared cover elements

struct CompanyMonogram: View {
    let name: String
    let background: Color
    let foreground: Color
    var size: CGFloat = 44
    /// nil renders a circle; a value renders a rounded square.
    var cornerRadius: CGFloat? = nil

    private var letter: String {
        name.first.map { String($0).uppercased() } ?? "•"
    }

    var body: some View {
        Text(letter)
            .font(.system(size: size * 0.48, weight: .black, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
    }
}

// Deterministic fake barcode for the editorial cover's corner. Widths come
// from an LCG over the seed so the same job always prints the same bars.
struct BarcodeMotif: View {
    let seed: String
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(Self.barWidths(seed: seed).enumerated()), id: \.offset) { _, width in
                Rectangle()
                    .fill(color)
                    .frame(width: width, height: 24)
            }
        }
    }

    static func barWidths(seed: String) -> [CGFloat] {
        var state = CarouselStyle.hash32(seed)
        var widths: [CGFloat] = []
        for _ in 0..<20 {
            state = state &* 1664525 &+ 1013904223
            switch (state >> 28) & 0b11 {
            case 0:  widths.append(1)
            case 1:  widths.append(1.5)
            case 2:  widths.append(2.5)
            default: widths.append(3.5)
            }
        }
        return widths
    }
}
