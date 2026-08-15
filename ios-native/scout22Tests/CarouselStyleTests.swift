import XCTest
import UIKit
@testable import scout22

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
    /// One representative backend theme id per palette family. Selection is
    /// family-scoped, so any test needing a specific family goes through this.
    static let themeIDPerFamily: [CarouselPaletteFamily: String] = [
        .cool: "slate-gradient",
        .warm: "sunset-paper",
        .earthy: "moss-grain",
        .playful: "neon-pop",
    ]

    // Guards the fixture above: if a theme id were regrouped backend-side,
    // every family-scoped test would silently exercise the wrong pool.
    func testThemeIDFixtureMapsToItsFamily() {
        for (family, themeID) in Self.themeIDPerFamily {
            XCTAssertEqual(CarouselPaletteFamily.family(forThemeID: themeID), family)
        }
        XCTAssertEqual(Set(Self.themeIDPerFamily.keys), Set(CarouselPaletteFamily.allCases))
    }

    // Same job + theme must always land on the same look — carousels
    // shouldn't reshuffle between scrolls or app launches.
    func testResolveIsDeterministic() {
        let a = CarouselStyle.resolve(jobID: "job-abc", themeID: "sunset-paper")
        let b = CarouselStyle.resolve(jobID: "job-abc", themeID: "sunset-paper")
        XCTAssertEqual(a, b)
    }

    // Every archetype must be reachable by some company. Selection is
    // per-family now, so no single theme id covers the whole roster — the
    // union across families must.
    func testEveryArchetypeIsReachableAcrossFamilies() {
        var seen = Set<CarouselArchetype>()
        for themeID in Self.themeIDPerFamily.values {
            for i in 0..<200 {
                seen.insert(CarouselStyle.resolve(jobID: "job-\(i)", themeID: themeID).archetype)
            }
        }
        XCTAssertEqual(seen, Set(CarouselArchetype.active))
    }

    // The structural version of the above: an archetype missing from every
    // pool would be dead code no company could ever surface.
    func testFamilyPoolsUnionToActive() {
        let union = Set(CarouselPaletteFamily.allCases.flatMap { CarouselArchetype.pool(for: $0) })
        XCTAssertEqual(union, Set(CarouselArchetype.active))
    }

    // The industry bias only holds if selection stays inside the family's
    // pool — a fintech job must never land on a bubblegum template.
    func testResolveStaysWithinItsFamilyPool() {
        for (family, themeID) in Self.themeIDPerFamily {
            let allowed = Set(CarouselArchetype.pool(for: family))
            for i in 0..<200 {
                let archetype = CarouselStyle.resolve(jobID: "job-\(i)", themeID: themeID).archetype
                XCTAssertTrue(allowed.contains(archetype), "\(archetype) escaped the \(family) pool")
            }
        }
    }

    // The hash must spread jobs across a family's whole pool — a feed of
    // same-industry jobs should still mix templates.
    func testFamilyPoolIsFullyCovered() {
        for (family, themeID) in Self.themeIDPerFamily {
            var seen = Set<CarouselArchetype>()
            for i in 0..<200 {
                seen.insert(CarouselStyle.resolve(jobID: "job-\(i)", themeID: themeID).archetype)
            }
            XCTAssertEqual(seen, Set(CarouselArchetype.pool(for: family)), "\(family) pool underused")
        }
    }

    // Dropping an archetype = removing it from the pool; it must never be
    // selected again and the remainder must absorb its jobs.
    func testDroppedArchetypeIsNeverSelected() {
        let pool = CarouselArchetype.active.filter { $0 != .handPainted }
        for i in 0..<300 {
            let style = CarouselStyle.resolve(jobID: "job-\(i)", themeID: "slate-gradient", pool: pool)
            XCTAssertNotEqual(style.archetype, .handPainted)
        }
    }

    // An empty pool (bad edit) must fail safe to a real archetype.
    func testEmptyPoolFallsBackToFirstTemplate() {
        let style = CarouselStyle.resolve(jobID: "job-1", themeID: "slate-gradient", pool: [])
        XCTAssertEqual(style.archetype, .boldDrop)
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
    // carries location/type/comp, the card drops it instead of ending the
    // carousel on a bare "the deets" header.
    func testEmptyDetailsSlideIsNotRenderable() throws {
        let job = try minimalJob()
        let empty = DetailsSlide(order: 3, location: nil, employment: nil, compensation: nil)
        XCTAssertFalse(empty.hasRenderableContent(for: job))

        let blank = DetailsSlide(order: 3, location: "", employment: nil, compensation: "")
        XCTAssertFalse(blank.hasRenderableContent(for: job))

        let located = DetailsSlide(order: 3, location: "NYC", employment: nil, compensation: nil)
        XCTAssertTrue(located.hasRenderableContent(for: job))

        let paid = DetailsSlide(order: 3, location: nil, employment: nil, compensation: "$150k+")
        XCTAssertTrue(paid.hasRenderableContent(for: job))
    }

    // Job-level fallbacks count as content — the view renders them even when
    // the slide's own fields are empty.
    func testDetailsSlideFallsBackToJobFields() throws {
        let job = try minimalJob(extra: ", \"location\": \"Remote\"")
        let empty = DetailsSlide(order: 3, location: nil, employment: nil, compensation: nil)
        XCTAssertTrue(empty.hasRenderableContent(for: job))
    }

    // Regression: the backend writes `employment_type`, and there is no
    // global keyDecodingStrategy — a missing CodingKeys mapping silently
    // decoded this as nil for the life of the feature.
    func testDetailsSlideDecodesEmploymentType() throws {
        let json = """
        {"type": "details", "order": 3, "location": "NYC",
         "employment_type": "Full-time", "compensation": "$150k+"}
        """.data(using: .utf8)!
        let slide = try JSONDecoder().decode(DetailsSlide.self, from: json)
        XCTAssertEqual(slide.employment, "Full-time")
        XCTAssertEqual(slide.location, "NYC")
        XCTAssertEqual(slide.compensation, "$150k+")
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
