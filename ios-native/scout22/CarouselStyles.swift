import SwiftUI

// Carousel layout archetypes — the second visual axis alongside the palette
// themes the backend assigns.
//
// The backend picks a theme_id per company (industry-biased, stable). The
// archetype is picked *client-side per job*, so one company's jobs land on
// different layouts and the feed reads like a mixed Instagram timeline
// instead of one template recolored ten ways. Nothing is persisted: the
// same job always resolves to the same archetype on every device.
//
// Every archetype is a true 4:5 card template rendered on a shared dark
// ground (CarouselCardTemplates.swift). Adding one: add a case, give it a
// palette accent below, add its cover + interior renderers, and append it to
// `CarouselArchetype.active`. Dropping one: remove it from `active` — jobs
// hashed to it redistribute across the remaining pool.

enum CarouselArchetype: String, CaseIterable {
    /// Cream type poster: teal part pill, navy/red stacked condensed caps.
    case boldDrop
    /// Cream collage zine: photo-slot blocks, italic stack, pay badge.
    case sundayEdit
    /// Bone fashion editorial: blurred figure, huge black type, script no.
    case motionEditorial
    /// Paper card on a warm blurred ground: bubble letters, sticker stars.
    case stickerScrapbook
    /// Cloud gradient, white heavy caps, scattered fact pills, pixel type.
    case daydreamY2K
    /// Butter yellow, per-letter multicolor headline, doodle stickers.
    case handPainted
    /// Greige serif elegance: blurred silhouette, caps + italic, capsules.
    case quietLuxury
    /// Sunlit warm still life: striped curtain light, vases, serif caps.
    case warmMinimal
    /// Dark lounge: blurred amber shapes, thin gold type, mono captions.
    case afterHours

    // Cut by product decision (restore from git history if wanted):
    // `editorial` newspaper (2026-07-18); `scrapbook` and `giantType`
    // (2026-07-22, superseded by stickerScrapbook / motionEditorial);
    // `poster` — the original pre-archetype layout (2026-07-22);
    // `neonCard` and `cyberGrid` full-bleeds (2026-07-29, template review);
    // `notification`, `glitchWindow`, `chromeStar` and `liquidChrome` — the
    // last full-bleed archetypes (2026-08-14). They were phone-height rather
    // than 4:5, which made them the only slides that couldn't be published
    // to Instagram; card templates cover the same visual range.

    /// Every archetype this build can draw. Selection happens per family
    /// (see `pool(for:)`); this list is the union and the registry that
    /// tests assert against.
    static let active: [CarouselArchetype] = [
        .boldDrop, .sundayEdit, .motionEditorial, .stickerScrapbook,
        .daydreamY2K, .handPainted, .quietLuxury,
        .warmMinimal, .afterHours,
    ]

    /// Selection pool for a palette family. Card templates hardcode their own
    /// interior art, so the backend's industry-biased theme_id can only reach
    /// a user through *which* template a job receives — pick from the subset
    /// whose mood suits the industry rather than repainting nine approved
    /// designs four ways. Without this the theme_id would have no client
    /// effect at all.
    ///
    /// Pools overlap deliberately, and every archetype in `active` appears in
    /// at least one (asserted by CarouselStyleTests). Selection within a pool
    /// is hash(job.id) mod count, so editing a pool reshuffles which job gets
    /// which look — safe, since the choice is never persisted anywhere.
    static func pool(for family: CarouselPaletteFamily) -> [CarouselArchetype] {
        switch family {
        // fintech, dev tools, infra, AI — restrained and typographic.
        case .cool:    return [.quietLuxury, .afterHours, .motionEditorial, .boldDrop]
        // consumer, marketplace, healthcare — sunlit and human.
        case .warm:    return [.warmMinimal, .sundayEdit, .handPainted]
        // climate, agtech, biotech — natural and unhurried.
        case .earthy:  return [.warmMinimal, .sundayEdit, .quietLuxury]
        // gaming, social, creator tools — loud and playful.
        case .playful: return [.daydreamY2K, .handPainted, .stickerScrapbook]
        }
    }
}

// Palette family, derived from the backend theme_id so the industry bias
// encoded in the theme choice (fintech ≠ bubblegum) carries into the
// archetype choice. Mirrors the grouping in _shared/themes.ts.
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
        // Unknown/future theme ids fall back to the most neutral family.
        default:                                               return .cool
        }
    }
}

struct CarouselStyle: Equatable {
    let archetype: CarouselArchetype
    let family: CarouselPaletteFamily
    let theme: CarouselTheme

    /// Deterministic per (job, company-theme): the backend theme id picks the
    /// palette family, the family picks the candidate pool, and the job id
    /// picks within it. `pool` is injectable so tests can pin a selection or
    /// prove dropped archetypes are never chosen.
    static func resolve(
        jobID: String,
        themeID: String,
        pool: [CarouselArchetype]? = nil
    ) -> CarouselStyle {
        let family = CarouselPaletteFamily.family(forThemeID: themeID)
        let pool = pool ?? CarouselArchetype.pool(for: family)
        guard !pool.isEmpty else {
            // Fail-safe for a bad pool edit: boldDrop, the first template.
            return CarouselStyle(
                archetype: .boldDrop,
                family: family,
                theme: CarouselArchetype.boldDrop.palette(for: family, themeID: themeID)
            )
        }
        let archetype = pool[Int(hash32(jobID) % UInt32(pool.count))]
        return CarouselStyle(archetype: archetype, family: family, theme: archetype.palette(for: family, themeID: themeID))
    }

    // FNV-1a 32-bit over UTF-8. Uniform enough for mod-N bucketing.
    static func hash32(_ input: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }
}

// MARK: - Style tokens

extension CarouselStyle {
    /// Foreground for text sitting on an accent-filled control (founder CTA,
    /// caption highlights). Every palette defines a readable ink for its
    /// accent.
    var onAccent: Color { theme.onAccent }
}

// MARK: - Per-archetype palettes

extension CarouselArchetype {
    /// Palette bundle for this archetype. Card templates keep one fixed
    /// palette (the approved preview look); the theme styles the dark ground
    /// and the shared feed chrome around the card.
    func palette(for family: CarouselPaletteFamily, themeID: String) -> CarouselTheme {
        switch self {
        case .boldDrop:         return CarouselArchetype.cardGround("card-bold-drop", accent: Color(red: 0.91, green: 0.25, blue: 0.11))
        case .sundayEdit:       return CarouselArchetype.cardGround("card-sunday-edit", accent: Color(red: 0.86, green: 0.89, blue: 0.42))
        case .motionEditorial:  return CarouselArchetype.cardGround("card-motion-editorial", accent: Color(red: 0.92, green: 0.91, blue: 0.89))
        case .stickerScrapbook: return CarouselArchetype.cardGround("card-sticker-scrapbook", accent: Color(red: 0.68, green: 0.80, blue: 0.92))
        case .daydreamY2K:      return CarouselArchetype.cardGround("card-daydream-y2k", accent: Color(red: 0.89, green: 0.34, blue: 0.55))
        case .handPainted:      return CarouselArchetype.cardGround("card-hand-painted", accent: Color(red: 0.91, green: 0.70, blue: 0.24))
        case .quietLuxury:      return CarouselArchetype.cardGround("card-quiet-luxury", accent: Color(red: 0.89, green: 0.85, blue: 0.80))
        case .warmMinimal:      return CarouselArchetype.cardGround("card-warm-minimal", accent: Color(red: 0.91, green: 0.84, blue: 0.72))
        case .afterHours:       return CarouselArchetype.cardGround("card-after-hours", accent: Color(red: 0.94, green: 0.85, blue: 0.54))
        }
    }

    /// Shared dark ground behind every 4:5 card template — the IG-feed
    /// framing from the approved preview.
    static func cardGround(_ id: String, accent: Color) -> CarouselTheme {
        CarouselTheme(
            id: id,
            backgroundTop:    Color(red: 0.07, green: 0.07, blue: 0.09),
            backgroundBottom: Color(red: 0.05, green: 0.05, blue: 0.07),
            accent:           accent,
            onAccent:         Color(red: 0.07, green: 0.07, blue: 0.09)
        )
    }
}

// MARK: - Cover fact helpers

enum CoverFacts {
    /// Human label for the LLM's experience_level enum, used by the card
    /// templates that surface seniority as a pill.
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
