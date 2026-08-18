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

    // Same company + theme must always land on the same look — carousels
    // shouldn't reshuffle between scrolls or app launches.
    func testResolveIsDeterministic() {
        let a = CarouselStyle.resolve(companyKey: "co-abc", themeID: "sunset-paper")
        let b = CarouselStyle.resolve(companyKey: "co-abc", themeID: "sunset-paper")
        XCTAssertEqual(a, b)
    }

    // The point of keying on the company: every open role at one employer
    // renders as the same template, so their posts read as one account.
    func testEveryRoleAtOneCompanyResolvesIdentically() {
        let first = CarouselStyle.resolve(companyKey: "co-lumen", themeID: "slate-gradient")
        for _ in 0..<50 {
            XCTAssertEqual(
                CarouselStyle.resolve(companyKey: "co-lumen", themeID: "slate-gradient"),
                first
            )
        }
    }

    // ...and different companies must still spread, or the feed becomes one
    // template. Guards against a key that collapses (e.g. an empty string).
    func testDifferentCompaniesSpreadAcrossThePool() {
        var seen = Set<CarouselArchetype>()
        for i in 0..<200 {
            seen.insert(CarouselStyle.resolve(companyKey: "co-\(i)", themeID: "slate-gradient").archetype)
        }
        XCTAssertEqual(seen, Set(CarouselArchetype.pool(for: .cool)))
    }

    // Every archetype must be reachable by some company. Selection is
    // per-family now, so no single theme id covers the whole roster — the
    // union across families must.
    func testEveryArchetypeIsReachableAcrossFamilies() {
        var seen = Set<CarouselArchetype>()
        for themeID in Self.themeIDPerFamily.values {
            for i in 0..<200 {
                seen.insert(CarouselStyle.resolve(companyKey: "co-\(i)", themeID: themeID).archetype)
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
                let archetype = CarouselStyle.resolve(companyKey: "co-\(i)", themeID: themeID).archetype
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
                seen.insert(CarouselStyle.resolve(companyKey: "co-\(i)", themeID: themeID).archetype)
            }
            XCTAssertEqual(seen, Set(CarouselArchetype.pool(for: family)), "\(family) pool underused")
        }
    }

    // Dropping an archetype = removing it from the pool; it must never be
    // selected again and the remainder must absorb its jobs.
    func testDroppedArchetypeIsNeverSelected() {
        let pool = CarouselArchetype.active.filter { $0 != .handPainted }
        for i in 0..<300 {
            let style = CarouselStyle.resolve(companyKey: "co-\(i)", themeID: "slate-gradient", pool: pool)
            XCTAssertNotEqual(style.archetype, .handPainted)
        }
    }

    // An empty pool (bad edit) must fail safe to a real archetype.
    func testEmptyPoolFallsBackToFirstTemplate() {
        let style = CarouselStyle.resolve(companyKey: "co-1", themeID: "slate-gradient", pool: [])
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

    // MARK: - Company key

    // The FK is preferred, then the embedded company row, then the
    // denormalised name — so rows carrying no company_id (reels, employer
    // posts) still group by employer instead of scattering per job.
    func testCompanyKeyPrefersTheForeignKey() throws {
        let job = try minimalJob(extra: """
        , "company_id": "co-1", "company": {"id": "co-2", "name": "Embedded"}
        """)
        XCTAssertEqual(job.carouselCompanyKey, "co-1")
    }

    func testCompanyKeyFallsBackToEmbeddedCompanyThenName() throws {
        let embedded = try minimalJob(extra: """
        , "company": {"id": "co-2", "name": "Embedded"}
        """)
        XCTAssertEqual(embedded.carouselCompanyKey, "co-2")

        // company_name only — the fixture's own fallback.
        let bare = try minimalJob()
        XCTAssertEqual(bare.carouselCompanyKey, "Acme")
    }

    // MARK: - Fact rail

    // Priority order is the contract every template renders against: the
    // fourth cell is always the level, whichever cover a job lands on.
    func testRailOrdersFactsByPriority() throws {
        let job = try minimalJob(extra: """
        , "location": "San Francisco, CA", "employment_type": "full_time"
        """)
        let cover = try coverSlide("""
        {"type": "cover", "order": 1, "compensation": "$165k-195k",
         "work_mode": "Hybrid", "experience": "senior"}
        """)
        let facts = CoverFacts.rail(cover, job)
        XCTAssertEqual(facts.map(\.label), ["comp", "location", "setup", "level", "type"])
        XCTAssertEqual(facts.first?.value, "$165k-195k")
    }

    // The whole point of the rail: a long location can't shrink the type, so
    // the region is dropped rather than scaled away.
    func testRailTrimsLocationToCity() throws {
        let job = try minimalJob()
        let cover = try coverSlide("""
        {"type": "cover", "order": 1, "location": "San Francisco, CA, United States"}
        """)
        let facts = CoverFacts.rail(cover, job)
        XCTAssertEqual(facts.first(where: { $0.label == "location" })?.value, "San Francisco")
    }

    // Missing and whitespace-only fields must vanish, not render as an empty
    // labelled cell with a hairline next to it.
    func testRailOmitsEmptyAndBlankFacts() throws {
        let job = try minimalJob()
        let cover = try coverSlide("""
        {"type": "cover", "order": 1, "compensation": "  ", "location": "",
         "work_mode": "Remote"}
        """)
        let facts = CoverFacts.rail(cover, job)
        XCTAssertEqual(facts.map(\.label), ["setup"])
    }

    // Experience is surfaced through the same label map the old pill used;
    // before the rail only one template of nine drew it at all.
    func testRailLabelsExperienceForHumans() throws {
        let job = try minimalJob()
        let cover = try coverSlide("""
        {"type": "cover", "order": 1, "experience": "entry"}
        """)
        XCTAssertEqual(CoverFacts.rail(cover, job).first?.value, "0-2 yrs")
    }

    // A job with nothing but a title yields an empty rail — templates must
    // draw no cells rather than a bare row of hairlines.
    func testRailIsEmptyWhenNothingIsKnown() throws {
        let job = try minimalJob()
        let cover = try coverSlide("""
        {"type": "cover", "order": 1}
        """)
        XCTAssertTrue(CoverFacts.rail(cover, job).isEmpty)
    }

    // MARK: - Title line balancing

    // The old split put the first two words on their own lines and joined the
    // whole remainder onto the third, so a long role rendered as two huge
    // words above one crammed line that shrank to a fraction of the size.
    func testLongTitleDoesNotDumpTheTailOnOneLine() {
        let words = ["SENIOR", "MANAGER", "DATA", "SCIENCE", "ANALYTICS"]
        let lines = balancedLines(words, into: 3)
        XCTAssertEqual(lines.count, 3)
        // The old behaviour produced "DATA SCIENCE ANALYTICS" — 22 chars.
        let longest = lines.map(\.count).max() ?? 0
        XCTAssertLessThanOrEqual(longest, 16, "tail line still crammed: \(lines)")
    }

    // Balancing must not lose or reorder words.
    func testBalancingPreservesEveryWordInOrder() {
        let words = ["STAFF", "SOFTWARE", "ENGINEER", "PLATFORM", "INFRA", "TEAM"]
        for count in 1...4 {
            let joined = balancedLines(words, into: count).joined(separator: " ")
            XCTAssertEqual(joined, words.joined(separator: " "), "count \(count) altered the title")
        }
    }

    // Fewer words than lines, or a single line, must pass straight through.
    func testBalancingHandlesShortTitles() {
        XCTAssertEqual(balancedLines(["IOS", "ENGINEER"], into: 3), ["IOS", "ENGINEER"])
        XCTAssertEqual(balancedLines(["DESIGNER"], into: 3), ["DESIGNER"])
        XCTAssertEqual(balancedLines(["HEAD", "OF", "DESIGN"], into: 1), ["HEAD OF DESIGN"])
    }

    // The split is the minimum-longest-line one, not merely "not the worst".
    func testBalancingMinimisesTheLongestLine() {
        // Optimal here is 14 ("PRODUCT DESIGN"); the naive split would be 23.
        let lines = balancedLines(["SENIOR", "PRODUCT", "DESIGN", "ENGINEER"], into: 3)
        XCTAssertEqual(lines.map(\.count).max(), 14, "expected an even split, got \(lines)")
    }

    // MARK: - Helpers

    private func coverSlide(_ json: String) throws -> CoverSlide {
        try JSONDecoder().decode(CoverSlide.self, from: Data(json.utf8))
    }

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
