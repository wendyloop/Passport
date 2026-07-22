import XCTest
import UIKit
@testable import JobTok

// The card templates draw with bundled faces; a missing or renamed font
// file silently falls back to the system font, so assert every PostScript
// name actually resolves after registration.
final class FontRegistrationTests: XCTestCase {
    func testAllBundledFontsRegister() {
        CarouselFonts.registerAll()
        for name in CarouselFonts.postScriptNames {
            XCTAssertNotNil(UIFont(name: name, size: 12), "font not registered: \(name)")
        }
    }
}

final class CarouselStyleTests: XCTestCase {
    // Same job + theme must always land on the same look — carousels
    // shouldn't reshuffle between scrolls or app launches.
    func testResolveIsDeterministic() {
        let a = CarouselStyle.resolve(jobID: "job-abc", themeID: "sunset-paper")
        let b = CarouselStyle.resolve(jobID: "job-abc", themeID: "sunset-paper")
        XCTAssertEqual(a, b)
    }

    // The hash must actually spread jobs across the whole active pool —
    // a feed of carousels should mix every archetype.
    func testActivePoolIsFullyCovered() {
        var seen = Set<CarouselArchetype>()
        for i in 0..<200 {
            seen.insert(CarouselStyle.resolve(jobID: "job-\(i)", themeID: "slate-gradient").archetype)
        }
        XCTAssertEqual(seen, Set(CarouselArchetype.active))
    }

    // Dropping an archetype = removing it from the pool; it must never be
    // selected again and the remainder must absorb its jobs.
    func testDroppedArchetypeIsNeverSelected() {
        let pool = CarouselArchetype.active.filter { $0 != .notification }
        for i in 0..<300 {
            let style = CarouselStyle.resolve(jobID: "job-\(i)", themeID: "slate-gradient", pool: pool)
            XCTAssertNotEqual(style.archetype, .notification)
        }
    }

    // An empty pool (bad edit) must fail safe to a real archetype.
    func testEmptyPoolFallsBackToNeonCard() {
        let style = CarouselStyle.resolve(jobID: "job-1", themeID: "slate-gradient", pool: [])
        XCTAssertEqual(style.archetype, .neonCard)
    }

    // Palette family mirrors the backend's industry-biased theme groups, and
    // unknown/future theme ids fall into the same family as the theme
    // resolver's slateGradient fallback.
    func testPaletteFamilyMapping() {
        for id in ["indigo-grid", "slate-gradient", "midnight-mono"] {
            XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: id), .cool)
        }
        for id in ["sunset-paper", "coral-soft", "amber-glow"] {
            XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: id), .warm)
        }
        for id in ["moss-grain", "clay-edge"] {
            XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: id), .earthy)
        }
        for id in ["neon-pop", "bubble-pastel"] {
            XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: id), .playful)
        }
        XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: "theme-from-the-future"), .cool)
    }

    // Every archetype must define a palette for every family — a gap here
    // would surface as a crash the first time a job hashes into the
    // missing combination.
    func testEveryArchetypeHasAPaletteForEveryFamily() {
        for archetype in CarouselArchetype.allCases {
            for family in CarouselPaletteFamily.allCases {
                let theme = archetype.palette(for: family, themeID: "slate-gradient")
                XCTAssertFalse(theme.id.isEmpty, "\(archetype) has no palette for \(family)")
            }
        }
    }

    // The backend always emits a details slide; when neither it nor the job
    // carries location/type/comp/perks, the card drops it instead of ending
    // the carousel on a bare "the deets" header.
    func testEmptyDetailsSlideIsNotRenderable() throws {
        let job = try minimalJob()
        let empty = DetailsSlide(order: 3, location: nil, employment: nil, compensation: nil, perks: nil)
        XCTAssertFalse(empty.hasRenderableContent(for: job))

        let blank = DetailsSlide(order: 3, location: "", employment: nil, compensation: "", perks: [])
        XCTAssertFalse(blank.hasRenderableContent(for: job))

        let located = DetailsSlide(order: 3, location: "NYC", employment: nil, compensation: nil, perks: nil)
        XCTAssertTrue(located.hasRenderableContent(for: job))

        let perked = DetailsSlide(order: 3, location: nil, employment: nil, compensation: nil, perks: ["equity"])
        XCTAssertTrue(perked.hasRenderableContent(for: job))
    }

    // Job-level fallbacks count as content — the view renders them even when
    // the slide's own fields are empty.
    func testDetailsSlideFallsBackToJobFields() throws {
        let job = try minimalJob(extra: ", \"location\": \"Remote\"")
        let empty = DetailsSlide(order: 3, location: nil, employment: nil, compensation: nil, perks: nil)
        XCTAssertTrue(empty.hasRenderableContent(for: job))
    }

    // MARK: - Helpers

    /// Bare job record with no location/type/comp; `extra` splices extra
    /// top-level JSON fields into the fixture.
    private func minimalJob(extra: String = "") throws -> JobPostingRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "job-min", "title": "Designer", "company_name": "Acme",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board"\(extra)}
        """.data(using: .utf8)!
        return try decoder.decode(JobPostingRecord.self, from: json)
    }
}
