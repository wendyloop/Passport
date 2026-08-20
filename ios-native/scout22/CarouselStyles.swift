import SwiftUI

// Carousel layout archetypes — the second visual axis alongside the palette
// themes the backend assigns.
//
// The archetype is picked *client-side per company*, so every role at one
// employer renders as a single identity and the feed still reads like a
// mixed Instagram timeline across employers. Nothing is persisted: the same
// company always resolves to the same archetype on every device.
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

    // Added 2026-08-16 from a second reference pass. Style only — palette,
    // face and layout; the copy is the job's own fields, never the reference's.

    /// Blush ground, maroon Didone, facts in a filled capsule.
    case boutiqueSerif
    /// Newsprint, typewriter mono, red condensed display, boxed facts.
    case pressClipping
    /// Translucent plate over a city ground, wide-tracked light caps.
    case panelPlate
    /// Oxblood poster, gold heavy caps, powder-blue marquee strips.
    case marqueePoster
    /// Cream filing drawer: one fact per pink folder tab, stamp cutout.
    case folderTabs
    /// Pale concrete wall, airy light caps, dark ink facts.
    case motionSplit

    // Cut by product decision (restore from git history if wanted):
    // `editorial` newspaper (2026-07-18); `scrapbook` and `giantType`
    // (2026-07-22, superseded by stickerScrapbook / motionEditorial);
    // `poster` — the original pre-archetype layout (2026-07-22);
    // `neonCard` and `cyberGrid` full-bleeds (2026-07-29, template review);
    // `notification`, `glitchWindow`, `chromeStar` and `liquidChrome` — the
    // last full-bleed archetypes (2026-08-14). They were phone-height rather
    // than 4:5, which made them the only slides that couldn't be published
    // to Instagram; card templates cover the same visual range.

    /// Every archetype this build can draw, and the pool selection draws
    /// from. Editing this list reshuffles which company gets which look —
    /// safe, since the choice is never persisted anywhere.
    static let active: [CarouselArchetype] = [
        .boldDrop, .sundayEdit, .motionEditorial, .stickerScrapbook,
        .daydreamY2K, .handPainted, .quietLuxury,
        .warmMinimal, .afterHours,
        .boutiqueSerif, .pressClipping, .panelPlate,
        .marqueePoster, .folderTabs, .motionSplit,
    ]

}

struct CarouselStyle: Equatable {
    let archetype: CarouselArchetype
    let theme: CarouselTheme

    /// Deterministic per company: the company key picks a template, and
    /// every role at that employer gets the same one.
    ///
    /// The backend's theme_id deliberately has no effect here. It encodes an
    /// industry bias (fintech vs gaming), but each card template hardcodes
    /// its own art, so honouring that bias would have meant restricting
    /// companies to a subset of the roster. Product call 2026-08-16: one
    /// consistent look per employer matters, matching the look to the
    /// industry does not.
    ///
    /// `pool` is injectable so tests can pin a selection or prove dropped
    /// archetypes are never chosen.
    static func resolve(
        companyKey: String,
        themeID: String = "",
        pool: [CarouselArchetype]? = nil
    ) -> CarouselStyle {
        let pool = pool ?? CarouselArchetype.active
        guard !pool.isEmpty else {
            // Fail-safe for a bad pool edit: boldDrop, the first template.
            return CarouselStyle(archetype: .boldDrop, theme: CarouselArchetype.boldDrop.palette())
        }
        let archetype = pool[Int(hash32(companyKey) % UInt32(pool.count))]
        return CarouselStyle(archetype: archetype, theme: archetype.palette())
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
    /// palette (the approved preview look); it only styles the dark ground
    /// and the shared feed chrome around the card, never the card art.
    func palette() -> CarouselTheme {
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
        case .boutiqueSerif:    return CarouselArchetype.cardGround("card-boutique-serif", accent: Color(red: 0.42, green: 0.07, blue: 0.13))
        case .pressClipping:    return CarouselArchetype.cardGround("card-press-clipping", accent: Color(red: 0.90, green: 0.14, blue: 0.11))
        case .panelPlate:       return CarouselArchetype.cardGround("card-panel-plate", accent: Color(red: 0.31, green: 0.55, blue: 0.77))
        case .marqueePoster:    return CarouselArchetype.cardGround("card-marquee-poster", accent: Color(red: 0.71, green: 0.64, blue: 0.29))
        case .folderTabs:       return CarouselArchetype.cardGround("card-folder-tabs", accent: Color(red: 0.94, green: 0.21, blue: 0.50))
        case .motionSplit:      return CarouselArchetype.cardGround("card-motion-split", accent: Color(red: 0.64, green: 0.62, blue: 0.57))
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

/// One labelled cell in a cover's fact rail.
struct CardFact: Equatable {
    let label: String
    let value: String
}

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

    /// City only. ATS locations arrive as "San Francisco, CA" or
    /// "San Francisco, CA, United States"; in a rail cell the region never
    /// earns its width, and it was the main thing dragging the old single
    /// meta line down to a 0.5 scale factor.
    static func city(_ raw: String) -> String {
        let head = raw.split(separator: ",").first.map(String.init) ?? raw
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// Cover facts in priority order: comp, location, setup, level, type.
    /// Templates take a prefix — cells drop from the right rather than
    /// shrinking, so a long location can never squeeze the type again.
    /// Empty and whitespace-only values are omitted entirely.
    static func rail(_ s: CoverSlide, _ job: JobPostingRecord) -> [CardFact] {
        var facts: [CardFact] = []
        func add(_ label: String, _ value: String?, transform: (String) -> String = { $0 }) {
            guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return }
            let out = transform(raw).trimmingCharacters(in: .whitespaces)
            guard !out.isEmpty else { return }
            facts.append(CardFact(label: label, value: out))
        }
        add("comp", s.compensation ?? job.compensationSummary ?? job.compensationText)
        add("location", s.location ?? job.location, transform: city)
        add("setup", s.workMode)
        add("level", s.experience, transform: experienceLabel)
        add("type", job.employmentType?.title)
        return facts
    }
}
