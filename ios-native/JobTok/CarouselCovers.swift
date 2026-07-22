import SwiftUI

// Archetype cover slides. Each archetype gets a fully custom cover — the
// first slide is what sells the scroll-stop — while interior slides share
// parameterized layouts in CarouselFeedCard.swift. All covers render the
// same underlying facts (CoverFacts) in their own visual language, use a
// letter monogram instead of the remote logo (deterministic, no network),
// and keep content above FeedLayout.slideContentClearance so the apply
// controls never overlap.

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


// MARK: - Glitch window (retro terminal)

struct GlitchWindowCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    private var companyName: String {
        slide.company ?? job.displayCompanyName
    }

    /// "Ramp Systems" → "RAMP.EXE" — first word only, so long names fit.
    private var windowTitle: String {
        let word = companyName.split(separator: " ").first.map(String.init) ?? companyName
        return word.uppercased() + ".EXE"
    }

    private var promptLine: String {
        "> " + (slide.role ?? job.title).lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private var metaLine: String {
        let facts = CoverFacts.build(slide: slide, job: job).prefix(2).map {
            $0.text.uppercased().replacingOccurrences(of: " ", with: "_")
        }
        return (facts + ["apply.now"]).joined(separator: " // ")
    }

    /// Decorative "match" percentage — deterministic per job, 70–95%.
    private var matchPercent: Int {
        70 + Int(CarouselStyle.hash32(job.id + "-match") % 26)
    }

    var body: some View {
        VStack {
            Spacer(minLength: 60)

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text(windowTitle)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(GlitchText.fringePink).frame(width: 7, height: 7)
                        Circle().fill(Color(red: 1.00, green: 0.75, blue: 0.28)).frame(width: 7, height: 7)
                        Circle().fill(theme.accent).frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.accent.opacity(0.8)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: 18) {
                    GlitchText(
                        text: "NOW\nHIRING",
                        font: .system(size: 40, weight: .black, design: .serif),
                        color: theme.textPrimary
                    )

                    Text(promptLine)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.14))
                                Rectangle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: proxy.size.width * CGFloat(matchPercent) / 100)
                            }
                        }
                        .frame(width: 130, height: 10)
                        Text("\(matchPercent)%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Text(metaLine)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(GlitchText.fringePink)
                        .lineLimit(2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.9), lineWidth: 1.5))

            Spacer()

            SwipeHint(theme: theme)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, FeedLayout.slideContentClearance)
    }
}

// Chromatic-aberration headline: the classic anaglyph magenta/cyan fringes
// behind the main fill. Fringe colors are universal, not palette-driven.
struct GlitchText: View {
    static let fringePink = Color(red: 1.00, green: 0.24, blue: 0.56)
    static let fringeCyan = Color(red: 0.22, green: 0.88, blue: 0.92)

    let text: String
    let font: Font
    let color: Color

    var body: some View {
        ZStack {
            Text(text).font(font).foregroundStyle(GlitchText.fringePink).offset(x: -1.6, y: 0.6)
            Text(text).font(font).foregroundStyle(GlitchText.fringeCyan).offset(x: 1.6, y: -0.6)
            Text(text).font(font).foregroundStyle(color)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chrome star (Y2K sparkle)

struct ChromeStarCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    private var companyName: String {
        slide.company ?? job.displayCompanyName
    }

    private var factLine: String? {
        let texts = CoverFacts.build(slide: slide, job: job).prefix(3).map(\.text)
        return texts.isEmpty ? nil : texts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 70)

            ZStack {
                SparkleShape()
                    .fill(SparkleShape.chrome)
                    .frame(width: 54, height: 54)
                    .offset(x: 30, y: -6)
                SparkleShape()
                    .fill(SparkleShape.chrome)
                    .frame(width: 18, height: 18)
                    .offset(x: -78, y: -18)
            }
            .frame(height: 76)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CompanyMonogram(
                        name: companyName,
                        background: Color(red: 0.82, green: 0.84, blue: 0.88),
                        foreground: theme.textPrimary,
                        size: 34
                    )
                    Text("\(companyName) is hiring")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Text(slide.role ?? job.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let factLine {
                    Text(factLine)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 5) {
                    Capsule().fill(theme.accent.opacity(0.75)).frame(width: 16, height: 5)
                    Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
                    Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.surface))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)

            Spacer()

            SwipeHint(theme: theme)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, FeedLayout.slideContentClearance)
    }
}

// Four-point sparkle with concave edges, filled with a chrome gradient.
struct SparkleShape: Shape {
    static let chrome = LinearGradient(
        colors: [
            Color.white,
            Color(red: 0.78, green: 0.80, blue: 0.84),
            Color(red: 0.55, green: 0.58, blue: 0.64),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Control points pulled toward the center make the edges concave.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var p = Path()
        p.move(to: pt(0.5, 0))
        p.addQuadCurve(to: pt(1, 0.5), control: pt(0.58, 0.42))
        p.addQuadCurve(to: pt(0.5, 1), control: pt(0.58, 0.58))
        p.addQuadCurve(to: pt(0, 0.5), control: pt(0.42, 0.58))
        p.addQuadCurve(to: pt(0.5, 0), control: pt(0.42, 0.42))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cyber grid (neon horizon)

struct CyberGridCoverView: View {
    let slide: CoverSlide
    let style: CarouselStyle
    let job: JobPostingRecord

    private var theme: CarouselTheme { style.theme }

    private var companyName: String {
        slide.company ?? job.displayCompanyName
    }

    private var metaLine: String? {
        let texts = CoverFacts.build(slide: slide, job: job).prefix(3).map { $0.text.uppercased() }
        return texts.isEmpty ? nil : texts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CompanyMonogram(
                        name: companyName,
                        background: theme.accent,
                        foreground: style.onAccent,
                        size: 34,
                        cornerRadius: 10
                    )
                    Text("\(companyName.uppercased()) IS HIRING")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(slide.role ?? job.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let metaLine {
                    Text(metaLine)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.accent.opacity(0.9), lineWidth: 1.2))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent)
                    .offset(x: -22, y: -6)
            }

            Spacer(minLength: 16)

            PerspectiveGridShape()
                .stroke(theme.accent.opacity(0.75), lineWidth: 1)
                .frame(height: 150)

            HStack(spacing: 5) {
                Capsule().fill(theme.accent).frame(width: 16, height: 5)
                Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
                Circle().fill(theme.textSecondary.opacity(0.4)).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, FeedLayout.slideContentClearance)
    }
}

// Tron-style one-point-perspective floor: rays fan out from a vanishing
// point on the horizon; horizontals bunch toward it quadratically.
struct PerspectiveGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let vanish = CGPoint(x: rect.midX, y: rect.minY)

        // Rays: bottom-edge targets spread past both sides so the outermost
        // lines exit through the rect's flanks.
        let spread: CGFloat = 1.7
        let rayCount = 11
        for i in 0..<rayCount {
            let t = CGFloat(i) / CGFloat(rayCount - 1)          // 0…1
            let x = rect.midX + (t - 0.5) * rect.width * spread
            p.move(to: vanish)
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        // Horizontals: quadratic spacing reads as depth.
        for i in 1...5 {
            let t = CGFloat(i) / 5
            let y = rect.minY + rect.height * t * t
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

// MARK: - Liquid chrome (dark metallic sheen)

struct LiquidChromeCoverView: View {
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
        VStack {
            Spacer(minLength: 70)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CompanyMonogram(
                        name: companyName,
                        background: Color.white.opacity(0.14),
                        foreground: theme.textPrimary,
                        size: 34
                    )
                    Text("\(companyName) is hiring")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Text(slide.role ?? job.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let factLine {
                    Text(factLine)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 5) {
                    Capsule().fill(theme.accent.opacity(0.9)).frame(width: 16, height: 5)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5)
                }
                .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LiquidChromeCardBackground())

            Spacer()

            SwipeHint(theme: theme)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, FeedLayout.slideContentClearance)
    }
}

// Gunmetal card with a soft top-left sheen. Shared by the liquid-chrome
// cover and its interior slides (SlideScaffold).
struct LiquidChromeCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.16, blue: 0.19),
                        Color(red: 0.10, green: 0.10, blue: 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.13), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 280
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

