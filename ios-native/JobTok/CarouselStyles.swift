import SwiftUI

// Carousel layout archetypes — the second visual axis alongside the palette
// themes in CarouselThemes.swift.
//
// The backend picks a theme_id per company (industry-biased, stable). The
// archetype is picked *client-side per job*, so one company's jobs land on
// different layouts and the feed reads like a mixed Instagram timeline
// instead of one template recolored ten ways. Nothing is persisted: the
// same job always resolves to the same archetype on every device.
//
// Adding an archetype: add a case, define its per-family palette below, add
// its cover in CarouselCovers.swift + chrome in CarouselFeedCard.swift, and
// append it to `CarouselArchetype.active`. Dropping one: remove it from
// `active` — jobs hashed to it redistribute across the remaining pool.

enum CarouselArchetype: String, CaseIterable {
    /// The original full-bleed layout (pre-archetype look).
    case poster
    /// Dark card with a glowing neon border and monogram byline.
    case neonCard
    /// Push-notification illustration on a pastel gradient wallpaper.
    /// Deliberately stylized (rotation, oversized corners, no clock) so it
    /// reads as an illustration, not a fake system notification.
    case notification
    /// Cream paper, italic serif, sticker chips, playful glyph accents.
    case scrapbook

    // An `editorial` newspaper archetype existed briefly and was cut by
    // product decision (2026-07-18) — restore from git history if wanted.

    /// The selection pool. Selection is hash(job.id) mod count, so editing
    /// this list reshuffles which job gets which look — safe, since the
    /// choice is never persisted anywhere.
    static let active: [CarouselArchetype] = [.poster, .neonCard, .notification, .scrapbook]
}

// Palette family, derived from the backend theme_id so the industry bias
// encoded in the theme choice (fintech ≠ bubblegum) carries into every
// archetype's palette. Mirrors the grouping in _shared/themes.ts.
enum CarouselPaletteFamily: CaseIterable {
    case cool      // indigo-grid, slate-gradient, midnight-mono
    case warm      // sunset-paper, coral-soft, amber-glow
    case earthy    // moss-grain, clay-edge
    case playful   // neon-pop, bubble-pastel

    static func family(forThemeID id: String) -> CarouselPaletteFamily {
        switch id {
        case "indigo-grid", "slate-gradient", "midnight-mono": return .cool
        case "sunset-paper", "coral-soft", "amber-glow":       return .warm
        case "moss-grain", "clay-edge":                        return .earthy
        case "neon-pop", "bubble-pastel":                      return .playful
        // Unknown/future theme ids: same fallback family as
        // CarouselTheme.resolve's slateGradient default.
        default:                                               return .cool
        }
    }
}

struct CarouselStyle: Equatable {
    let archetype: CarouselArchetype
    let family: CarouselPaletteFamily
    let theme: CarouselTheme

    /// Deterministic per (job, company-theme): archetype from the job id,
    /// palette family from the backend theme id. `pool` is injectable so
    /// tests can prove dropped archetypes are never selected.
    static func resolve(
        jobID: String,
        themeID: String,
        pool: [CarouselArchetype] = CarouselArchetype.active
    ) -> CarouselStyle {
        let family = CarouselPaletteFamily.family(forThemeID: themeID)
        guard !pool.isEmpty else {
            return CarouselStyle(archetype: .poster, family: family, theme: CarouselTheme.resolve(themeID))
        }
        let archetype = pool[Int(hash32(jobID) % UInt32(pool.count))]
        return CarouselStyle(archetype: archetype, family: family, theme: archetype.palette(for: family, themeID: themeID))
    }

    // FNV-1a 32-bit over UTF-8. Uniform enough for mod-N bucketing; keep
    // independent from the poster cover's scalar-sum layout toggle so the
    // two choices don't correlate.
    static func hash32(_ input: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }
}

// MARK: - Style tokens shared by interior slides

extension CarouselStyle {
    /// Section-header font for interior slides ("the backstory", "the deets").
    var headerFont: Font {
        switch archetype {
        case .poster:       return theme.titleFont
        case .neonCard:     return .system(size: 24, weight: .heavy, design: .rounded)
        case .notification: return .system(size: 22, weight: .bold)
        case .scrapbook:    return .system(size: 26, weight: .bold, design: .serif).italic()
        }
    }

    var headerColor: Color {
        archetype == .scrapbook ? theme.accent : theme.textPrimary
    }

    /// Header copy transform: notification reads like a notification title,
    /// everyone else keeps the lowercase feed voice.
    func headerText(_ raw: String) -> String {
        switch archetype {
        case .notification: return raw.prefix(1).uppercased() + raw.dropFirst()
        default:            return raw
        }
    }

    /// Foreground for text sitting on an accent-filled control (founder CTA,
    /// caption highlights). Every palette — legacy themes included — defines
    /// a readable ink for its accent.
    var onAccent: Color { theme.onAccent }

    /// Decorative glyph for the scrapbook archetype, seeded by family so it
    /// matches the palette (cherries on cream, leaves on sage, …).
    var scrapbookDecor: String {
        switch family {
        case .cool:    return "⭐️"
        case .warm:    return "🍒"
        case .earthy:  return "🌿"
        case .playful: return "🌸"
        }
    }
}

// MARK: - Per-archetype palettes

extension CarouselArchetype {
    /// Palette bundle for this archetype in the given family. Poster keeps
    /// resolving the backend theme id directly — it *is* the legacy look.
    func palette(for family: CarouselPaletteFamily, themeID: String) -> CarouselTheme {
        switch self {
        case .poster:       return CarouselTheme.resolve(themeID)
        case .neonCard:     return CarouselArchetype.neonCardPalettes[family]!
        case .notification: return CarouselArchetype.notificationPalettes[family]!
        case .scrapbook:    return CarouselArchetype.scrapbookPalettes[family]!
        }
    }


    // Near-black ground, one neon accent doing all the work.
    private static let neonCardPalettes: [CarouselPaletteFamily: CarouselTheme] = [
        .cool: CarouselTheme(
            id: "neon-card-cool",
            backgroundTop:    Color(red: 0.04, green: 0.05, blue: 0.08),
            backgroundBottom: Color(red: 0.07, green: 0.09, blue: 0.13),
            surface:          Color.white.opacity(0.05),
            accent:           Color(red: 0.35, green: 0.85, blue: 1.00),
            textPrimary:      Color(red: 0.96, green: 0.97, blue: 0.95),
            textSecondary:    Color.white.opacity(0.62),
            onAccent:         Color(red: 0.04, green: 0.05, blue: 0.08),
            bulletGlyph:      "chevron.right",
            titleFont:        .system(size: 30, weight: .heavy, design: .rounded),
            bodyFont:         .system(size: 16, weight: .medium, design: .rounded)
        ),
        .warm: CarouselTheme(
            id: "neon-card-warm",
            backgroundTop:    Color(red: 0.07, green: 0.05, blue: 0.03),
            backgroundBottom: Color(red: 0.11, green: 0.08, blue: 0.05),
            surface:          Color.white.opacity(0.05),
            accent:           Color(red: 1.00, green: 0.72, blue: 0.25),
            textPrimary:      Color(red: 0.98, green: 0.96, blue: 0.92),
            textSecondary:    Color.white.opacity(0.62),
            onAccent:         Color(red: 0.07, green: 0.05, blue: 0.03),
            bulletGlyph:      "chevron.right",
            titleFont:        .system(size: 30, weight: .heavy, design: .rounded),
            bodyFont:         .system(size: 16, weight: .medium, design: .rounded)
        ),
        .earthy: CarouselTheme(
            id: "neon-card-earthy",
            backgroundTop:    Color(red: 0.04, green: 0.07, blue: 0.04),
            backgroundBottom: Color(red: 0.07, green: 0.11, blue: 0.07),
            surface:          Color.white.opacity(0.05),
            accent:           Color(red: 0.62, green: 0.95, blue: 0.30),
            textPrimary:      Color(red: 0.95, green: 0.98, blue: 0.93),
            textSecondary:    Color.white.opacity(0.62),
            onAccent:         Color(red: 0.04, green: 0.07, blue: 0.04),
            bulletGlyph:      "chevron.right",
            titleFont:        .system(size: 30, weight: .heavy, design: .rounded),
            bodyFont:         .system(size: 16, weight: .medium, design: .rounded)
        ),
        .playful: CarouselTheme(
            id: "neon-card-playful",
            backgroundTop:    Color(red: 0.08, green: 0.03, blue: 0.08),
            backgroundBottom: Color(red: 0.12, green: 0.05, blue: 0.13),
            surface:          Color.white.opacity(0.05),
            accent:           Color(red: 1.00, green: 0.36, blue: 0.75),
            textPrimary:      Color(red: 0.98, green: 0.95, blue: 0.97),
            textSecondary:    Color.white.opacity(0.62),
            onAccent:         Color(red: 0.08, green: 0.03, blue: 0.08),
            bulletGlyph:      "chevron.right",
            titleFont:        .system(size: 30, weight: .heavy, design: .rounded),
            bodyFont:         .system(size: 16, weight: .medium, design: .rounded)
        ),
    ]

    // Pastel wallpaper behind white cards. textPrimary is the on-card ink;
    // textSecondary must read on both the card and the wallpaper.
    private static let notificationPalettes: [CarouselPaletteFamily: CarouselTheme] = [
        .cool: CarouselTheme(
            id: "notification-cool",
            backgroundTop:    Color(red: 0.81, green: 0.81, blue: 0.95),
            backgroundBottom: Color(red: 0.90, green: 0.83, blue: 0.93),
            surface:          Color.white.opacity(0.96),
            accent:           Color(red: 0.34, green: 0.34, blue: 0.72),
            textPrimary:      Color(red: 0.13, green: 0.13, blue: 0.20),
            textSecondary:    Color(red: 0.38, green: 0.38, blue: 0.52),
            bulletGlyph:      "circle.fill",
            titleFont:        .system(size: 28, weight: .bold),
            bodyFont:         .system(size: 16, weight: .regular)
        ),
        .warm: CarouselTheme(
            id: "notification-warm",
            backgroundTop:    Color(red: 0.99, green: 0.87, blue: 0.79),
            backgroundBottom: Color(red: 0.97, green: 0.78, blue: 0.80),
            surface:          Color.white.opacity(0.96),
            accent:           Color(red: 0.78, green: 0.30, blue: 0.24),
            textPrimary:      Color(red: 0.22, green: 0.12, blue: 0.09),
            textSecondary:    Color(red: 0.48, green: 0.33, blue: 0.29),
            bulletGlyph:      "circle.fill",
            titleFont:        .system(size: 28, weight: .bold),
            bodyFont:         .system(size: 16, weight: .regular)
        ),
        .earthy: CarouselTheme(
            id: "notification-earthy",
            backgroundTop:    Color(red: 0.84, green: 0.92, blue: 0.86),
            backgroundBottom: Color(red: 0.77, green: 0.88, blue: 0.81),
            surface:          Color.white.opacity(0.96),
            accent:           Color(red: 0.18, green: 0.44, blue: 0.30),
            textPrimary:      Color(red: 0.10, green: 0.17, blue: 0.12),
            textSecondary:    Color(red: 0.30, green: 0.42, blue: 0.34),
            bulletGlyph:      "circle.fill",
            titleFont:        .system(size: 28, weight: .bold),
            bodyFont:         .system(size: 16, weight: .regular)
        ),
        .playful: CarouselTheme(
            id: "notification-playful",
            backgroundTop:    Color(red: 1.00, green: 0.84, blue: 0.92),
            backgroundBottom: Color(red: 0.79, green: 0.86, blue: 1.00),
            surface:          Color.white.opacity(0.96),
            accent:           Color(red: 0.55, green: 0.29, blue: 0.78),
            textPrimary:      Color(red: 0.17, green: 0.11, blue: 0.24),
            textSecondary:    Color(red: 0.40, green: 0.32, blue: 0.50),
            bulletGlyph:      "circle.fill",
            titleFont:        .system(size: 28, weight: .bold),
            bodyFont:         .system(size: 16, weight: .regular)
        ),
    ]

    // Cream paper + one fruity accent; surface is the sticker fill.
    private static let scrapbookPalettes: [CarouselPaletteFamily: CarouselTheme] = [
        .cool: CarouselTheme(
            id: "scrapbook-cool",
            backgroundTop:    Color(red: 0.97, green: 0.96, blue: 0.92),
            backgroundBottom: Color(red: 0.94, green: 0.94, blue: 0.90),
            surface:          Color.white,
            accent:           Color(red: 0.27, green: 0.32, blue: 0.66),
            textPrimary:      Color(red: 0.16, green: 0.15, blue: 0.18),
            textSecondary:    Color(red: 0.40, green: 0.39, blue: 0.44),
            onAccent:         Color(red: 0.99, green: 0.97, blue: 0.93),
            bulletGlyph:      "star.fill",
            titleFont:        .system(size: 30, weight: .bold, design: .serif).italic(),
            bodyFont:         .system(size: 16, weight: .medium, design: .serif)
        ),
        .warm: CarouselTheme(
            id: "scrapbook-warm",
            backgroundTop:    Color(red: 0.99, green: 0.95, blue: 0.89),
            backgroundBottom: Color(red: 0.98, green: 0.92, blue: 0.86),
            surface:          Color.white,
            accent:           Color(red: 0.75, green: 0.13, blue: 0.21),
            textPrimary:      Color(red: 0.21, green: 0.12, blue: 0.10),
            textSecondary:    Color(red: 0.46, green: 0.33, blue: 0.29),
            onAccent:         Color(red: 0.99, green: 0.97, blue: 0.93),
            bulletGlyph:      "heart.fill",
            titleFont:        .system(size: 30, weight: .bold, design: .serif).italic(),
            bodyFont:         .system(size: 16, weight: .medium, design: .serif)
        ),
        .earthy: CarouselTheme(
            id: "scrapbook-earthy",
            backgroundTop:    Color(red: 0.96, green: 0.96, blue: 0.89),
            backgroundBottom: Color(red: 0.92, green: 0.93, blue: 0.85),
            surface:          Color.white,
            accent:           Color(red: 0.33, green: 0.42, blue: 0.17),
            textPrimary:      Color(red: 0.14, green: 0.16, blue: 0.10),
            textSecondary:    Color(red: 0.36, green: 0.40, blue: 0.30),
            onAccent:         Color(red: 0.99, green: 0.97, blue: 0.93),
            bulletGlyph:      "leaf.fill",
            titleFont:        .system(size: 30, weight: .bold, design: .serif).italic(),
            bodyFont:         .system(size: 16, weight: .medium, design: .serif)
        ),
        .playful: CarouselTheme(
            id: "scrapbook-playful",
            backgroundTop:    Color(red: 1.00, green: 0.95, blue: 0.96),
            backgroundBottom: Color(red: 0.98, green: 0.91, blue: 0.94),
            surface:          Color.white,
            accent:           Color(red: 0.84, green: 0.25, blue: 0.55),
            textPrimary:      Color(red: 0.20, green: 0.12, blue: 0.16),
            textSecondary:    Color(red: 0.45, green: 0.33, blue: 0.39),
            onAccent:         Color(red: 0.99, green: 0.97, blue: 0.93),
            bulletGlyph:      "sparkles",
            titleFont:        .system(size: 30, weight: .bold, design: .serif).italic(),
            bodyFont:         .system(size: 16, weight: .medium, design: .serif)
        ),
    ]
}

// MARK: - Cover fact extraction

// The scannable facts every cover renders in its own visual style. Order =
// decision weight from job-seeker research: salary first (89% call it the
// most helpful element), then experience fit, work mode, location, type,
// freshness. Extracted from CoverSlideView so all archetype covers share it.
struct CoverFact: Equatable, Identifiable {
    let icon: String
    let text: String
    var id: String { icon + text }
}

enum CoverFacts {
    static func build(slide: CoverSlide, job: JobPostingRecord) -> [CoverFact] {
        var facts: [CoverFact] = []
        let comp = slide.compensation ?? job.compensationSummary ?? job.compensationText
        if let comp, !comp.isEmpty {
            facts.append(CoverFact(icon: "dollarsign.circle.fill", text: comp))
        }
        if let exp = slide.experience, !exp.isEmpty {
            facts.append(CoverFact(icon: "chart.bar.fill", text: experienceLabel(exp)))
        }
        if let mode = slide.workMode, !mode.isEmpty {
            facts.append(CoverFact(icon: "house.fill", text: mode))
        }
        if let loc = slide.location ?? job.location, !loc.isEmpty {
            facts.append(CoverFact(icon: "mappin.and.ellipse", text: loc))
        }
        if let type = job.employmentType?.title {
            facts.append(CoverFact(icon: "briefcase.fill", text: type))
        }
        facts.append(CoverFact(icon: "clock.fill", text: SharedFormatters.relativeAge(of: job.createdAt)))
        return facts
    }

    static func experienceLabel(_ raw: String) -> String {
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
}
