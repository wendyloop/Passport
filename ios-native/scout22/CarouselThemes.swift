import SwiftUI

// Palette bundle for a carousel card.
//
// Card templates hardcode their own interior art (see CarouselCardTemplates),
// so a theme only describes the shared chrome around the card: the dark feed
// ground behind it and the accent used by grid tiles and accent-filled
// controls. Instances come from `CarouselArchetype.cardGround`.
//
// This used to be a 10-entry registry of full palettes (typography, bullet
// glyphs, surfaces) keyed by the backend's theme_id, consumed by the
// full-bleed archetypes. Those were removed 2026-08-14 and the registry went
// with them — the backend's theme_id now reaches the client only through
// CarouselPaletteFamily.

struct CarouselTheme: Equatable {
    let id: String
    let backgroundTop: Color
    let backgroundBottom: Color
    let accent: Color
    /// Ink for text sitting on an accent-filled control (grid-tile monogram,
    /// caption highlight). Defaults to white, which reads on dark accents;
    /// palettes with light accents override with a dark ink.
    var onAccent: Color = .white

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
