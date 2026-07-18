import XCTest
@testable import JobTok

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

    // Poster is the legacy look: it must keep resolving the backend theme
    // id directly, not an archetype palette.
    func testPosterUsesBackendTheme() throws {
        let jobID = try XCTUnwrap(firstJobID(resolvingTo: .poster, themeID: "sunset-paper"))
        let style = CarouselStyle.resolve(jobID: jobID, themeID: "sunset-paper")
        XCTAssertEqual(style.theme, CarouselTheme.resolve("sunset-paper"))
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

    // An empty pool (bad edit) must fail safe to the legacy poster look.
    func testEmptyPoolFallsBackToPoster() {
        let style = CarouselStyle.resolve(jobID: "job-1", themeID: "slate-gradient", pool: [])
        XCTAssertEqual(style.archetype, .poster)
        XCTAssertEqual(style.theme, CarouselTheme.resolve("slate-gradient"))
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

    // Every non-poster archetype must define a palette for every family —
    // a gap here would surface as a crash the first time a job hashes into
    // the missing combination.
    func testEveryArchetypeHasAPaletteForEveryFamily() {
        for archetype in CarouselArchetype.allCases {
            for family in CarouselPaletteFamily.allCases {
                let theme = archetype.palette(for: family, themeID: "slate-gradient")
                XCTAssertFalse(theme.id.isEmpty, "\(archetype) has no palette for \(family)")
            }
        }
    }

    // The barcode motif is part of a deterministic cover: same job, same bars.
    func testBarcodeWidthsAreDeterministic() {
        XCTAssertEqual(BarcodeMotif.barWidths(seed: "job-1"), BarcodeMotif.barWidths(seed: "job-1"))
        XCTAssertEqual(BarcodeMotif.barWidths(seed: "job-1").count, 20)
    }

    // MARK: - Helpers

    /// First synthetic job id whose default-pool resolution lands on the
    /// given archetype. Deterministic; also used by the render smoke tests.
    private func firstJobID(resolvingTo archetype: CarouselArchetype, themeID: String) -> String? {
        (0..<200)
            .map { "job-\($0)" }
            .first { CarouselStyle.resolve(jobID: $0, themeID: themeID).archetype == archetype }
    }
}
