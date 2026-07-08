import SwiftUI

// Carousel theme registry. Mirrors supabase/functions/_shared/themes.ts.
// The backend picks a theme_id deterministically per (company, industry); the
// app resolves it to a visual bundle at render time. Unknown IDs fall back
// to `slateGradient` so a future backend addition never crashes the feed.

struct CarouselTheme: Equatable {
    let id: String
    let backgroundTop: Color
    let backgroundBottom: Color
    let surface: Color
    let accent: Color
    let textPrimary: Color
    let textSecondary: Color
    let bulletGlyph: String           // SF Symbol used for list bullets
    let titleFont: Font
    let bodyFont: Font

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension CarouselTheme {
    static let registry: [String: CarouselTheme] = [
        // Cool / minimalist
        "indigo-grid":     .indigoGrid,
        "slate-gradient":  .slateGradient,
        "midnight-mono":   .midnightMono,
        // Warm / human
        "sunset-paper":    .sunsetPaper,
        "coral-soft":      .coralSoft,
        "amber-glow":      .amberGlow,
        // Earthy / organic
        "moss-grain":      .mossGrain,
        "clay-edge":       .clayEdge,
        // Playful / bold
        "neon-pop":        .neonPop,
        "bubble-pastel":   .bubblePastel,
    ]

    static func resolve(_ id: String) -> CarouselTheme {
        registry[id] ?? slateGradient
    }

    // MARK: - Concrete themes

    static let indigoGrid = CarouselTheme(
        id: "indigo-grid",
        backgroundTop:    Color(red: 0.07, green: 0.10, blue: 0.22),
        backgroundBottom: Color(red: 0.14, green: 0.18, blue: 0.36),
        surface:          Color.white.opacity(0.08),
        accent:           Color(red: 0.45, green: 0.62, blue: 1.00),
        textPrimary:      .white,
        textSecondary:    Color.white.opacity(0.72),
        bulletGlyph:      "square.grid.2x2.fill",
        titleFont:        .system(size: 32, weight: .heavy, design: .rounded),
        bodyFont:         .system(size: 17, weight: .medium, design: .rounded)
    )

    static let slateGradient = CarouselTheme(
        id: "slate-gradient",
        backgroundTop:    Color(red: 0.10, green: 0.12, blue: 0.16),
        backgroundBottom: Color(red: 0.22, green: 0.26, blue: 0.34),
        surface:          Color.white.opacity(0.08),
        accent:           Color(red: 0.55, green: 0.82, blue: 0.95),
        textPrimary:      .white,
        textSecondary:    Color.white.opacity(0.70),
        bulletGlyph:      "circle.fill",
        titleFont:        .system(size: 32, weight: .heavy, design: .rounded),
        bodyFont:         .system(size: 17, weight: .medium, design: .rounded)
    )

    static let midnightMono = CarouselTheme(
        id: "midnight-mono",
        backgroundTop:    .black,
        backgroundBottom: Color(red: 0.10, green: 0.10, blue: 0.12),
        surface:          Color.white.opacity(0.06),
        accent:           .white,
        textPrimary:      .white,
        textSecondary:    Color.white.opacity(0.62),
        bulletGlyph:      "line.diagonal",
        titleFont:        .system(size: 30, weight: .heavy, design: .monospaced),
        bodyFont:         .system(size: 16, weight: .medium, design: .monospaced)
    )

    static let sunsetPaper = CarouselTheme(
        id: "sunset-paper",
        backgroundTop:    Color(red: 0.99, green: 0.93, blue: 0.86),
        backgroundBottom: Color(red: 0.96, green: 0.78, blue: 0.65),
        surface:          Color.black.opacity(0.05),
        accent:           Color(red: 0.85, green: 0.30, blue: 0.32),
        textPrimary:      Color(red: 0.18, green: 0.12, blue: 0.12),
        textSecondary:    Color(red: 0.35, green: 0.25, blue: 0.22),
        bulletGlyph:      "sun.max.fill",
        titleFont:        .system(size: 32, weight: .heavy, design: .serif),
        bodyFont:         .system(size: 17, weight: .medium, design: .serif)
    )

    static let coralSoft = CarouselTheme(
        id: "coral-soft",
        backgroundTop:    Color(red: 1.00, green: 0.86, blue: 0.82),
        backgroundBottom: Color(red: 0.99, green: 0.62, blue: 0.55),
        surface:          Color.white.opacity(0.35),
        accent:           Color(red: 0.78, green: 0.18, blue: 0.30),
        textPrimary:      Color(red: 0.20, green: 0.08, blue: 0.10),
        textSecondary:    Color(red: 0.36, green: 0.18, blue: 0.20),
        bulletGlyph:      "heart.fill",
        titleFont:        .system(size: 32, weight: .heavy, design: .rounded),
        bodyFont:         .system(size: 17, weight: .medium, design: .rounded)
    )

    static let amberGlow = CarouselTheme(
        id: "amber-glow",
        backgroundTop:    Color(red: 1.00, green: 0.78, blue: 0.36),
        backgroundBottom: Color(red: 0.90, green: 0.46, blue: 0.18),
        surface:          Color.white.opacity(0.20),
        accent:           Color(red: 0.30, green: 0.12, blue: 0.05),
        textPrimary:      Color(red: 0.18, green: 0.08, blue: 0.02),
        textSecondary:    Color(red: 0.36, green: 0.20, blue: 0.10),
        bulletGlyph:      "sparkles",
        titleFont:        .system(size: 32, weight: .black, design: .rounded),
        bodyFont:         .system(size: 17, weight: .semibold, design: .rounded)
    )

    static let mossGrain = CarouselTheme(
        id: "moss-grain",
        backgroundTop:    Color(red: 0.16, green: 0.28, blue: 0.20),
        backgroundBottom: Color(red: 0.30, green: 0.42, blue: 0.28),
        surface:          Color.white.opacity(0.10),
        accent:           Color(red: 0.85, green: 0.92, blue: 0.55),
        textPrimary:      Color(red: 0.96, green: 0.95, blue: 0.88),
        textSecondary:    Color(red: 0.82, green: 0.84, blue: 0.74),
        bulletGlyph:      "leaf.fill",
        titleFont:        .system(size: 32, weight: .heavy, design: .serif),
        bodyFont:         .system(size: 17, weight: .medium, design: .serif)
    )

    static let clayEdge = CarouselTheme(
        id: "clay-edge",
        backgroundTop:    Color(red: 0.86, green: 0.66, blue: 0.50),
        backgroundBottom: Color(red: 0.62, green: 0.38, blue: 0.26),
        surface:          Color.white.opacity(0.22),
        accent:           Color(red: 0.30, green: 0.14, blue: 0.08),
        textPrimary:      Color(red: 0.22, green: 0.10, blue: 0.05),
        textSecondary:    Color(red: 0.38, green: 0.22, blue: 0.14),
        bulletGlyph:      "circle.dashed",
        titleFont:        .system(size: 32, weight: .heavy, design: .serif),
        bodyFont:         .system(size: 17, weight: .medium, design: .serif)
    )

    static let neonPop = CarouselTheme(
        id: "neon-pop",
        backgroundTop:    Color(red: 0.05, green: 0.02, blue: 0.20),
        backgroundBottom: Color(red: 0.18, green: 0.02, blue: 0.30),
        surface:          Color.white.opacity(0.08),
        accent:           Color(red: 0.20, green: 1.00, blue: 0.65),
        textPrimary:      .white,
        textSecondary:    Color(red: 0.90, green: 0.65, blue: 1.00),
        bulletGlyph:      "bolt.fill",
        titleFont:        .system(size: 34, weight: .black, design: .rounded),
        bodyFont:         .system(size: 17, weight: .bold, design: .rounded)
    )

    static let bubblePastel = CarouselTheme(
        id: "bubble-pastel",
        backgroundTop:    Color(red: 1.00, green: 0.85, blue: 0.95),
        backgroundBottom: Color(red: 0.78, green: 0.86, blue: 1.00),
        surface:          Color.white.opacity(0.55),
        accent:           Color(red: 0.62, green: 0.28, blue: 0.80),
        textPrimary:      Color(red: 0.18, green: 0.10, blue: 0.28),
        textSecondary:    Color(red: 0.36, green: 0.24, blue: 0.46),
        bulletGlyph:      "circle.hexagongrid.fill",
        titleFont:        .system(size: 32, weight: .black, design: .rounded),
        bodyFont:         .system(size: 17, weight: .semibold, design: .rounded)
    )
}
