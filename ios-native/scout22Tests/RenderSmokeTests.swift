import XCTest
import SwiftUI
@testable import scout22

// T7 (first pass): render smoke tests via ImageRenderer — catches
// crash-on-render and zero-size regressions in the feed's key views.
// Pixel-diff snapshots (swift-snapshot-testing) remain a deferred upgrade.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.uiImage
    }

    func testCarouselCardRenders() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "job-1", "title": "iOS Engineer", "company_name": "Acme",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board", "company_id": "co-1",
         "company": {"id": "co-1", "name": "Acme", "stage": "seed"},
         "carousel": {"theme_id": "slate-gradient", "slide_count": 3, "status": "generated",
           "content": [
             {"type": "cover", "order": 1, "role": "iOS Engineer", "company": "Acme",
              "location": "NYC", "compensation": "$150k+", "youd_line": "you'd build the app",
              "experience": "entry", "work_mode": "remote"},
             {"type": "founder", "order": 2, "name": "Jane Doe", "role_title": "CEO"},
             {"type": "details", "order": 3, "location": "NYC"}
           ]}}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        let carousel = try XCTUnwrap(job.carousel)

        let image = render(CarouselFeedCard(
            job: job,
            carousel: carousel,
            safeAreaBottom: 34,
            isActive: false,
            onApply: {},
            onEmailFounder: {},
            onSave: {},
            isSaved: false
        ))
        let unwrapped = try XCTUnwrap(image, "carousel card failed to render")
        XCTAssertGreaterThan(unwrapped.size.width, 300)
        XCTAssertGreaterThan(unwrapped.size.height, 600)
    }

    // Every layout archetype must render every slide type without crashing
    // or collapsing to zero size. Job ids are brute-forced per archetype so
    // the card's internal CarouselStyle.resolve lands where we want.
    func testCarouselCardRendersEveryArchetype() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for archetype in CarouselArchetype.active {
            // Selection is family-scoped, so drive each archetype through a
            // family whose pool actually contains it — the card resolves its
            // own style internally from the theme id in this fixture.
            let family = try XCTUnwrap(
                CarouselPaletteFamily.allCases.first {
                    CarouselArchetype.pool(for: $0).contains(archetype)
                },
                "\(archetype) is in no family pool"
            )
            let themeID = try XCTUnwrap(CarouselStyleTests.themeIDPerFamily[family])
            // Selection keys on the company, not the job, so the company id is
            // what has to be brute-forced to steer the card onto an archetype.
            let companyID = try XCTUnwrap(
                (0..<400).map({ "smoke-co-\($0)" }).first {
                    CarouselStyle.resolve(companyKey: $0, themeID: themeID).archetype == archetype
                },
                "no synthetic company id resolves to \(archetype)"
            )

            let json = """
            {"id": "smoke-job-\(archetype.rawValue)", "title": "Senior Product Designer",
             "company_name": "Ramp",
             "is_published": true, "created_at": "2026-07-01T12:00:00Z",
             "source_kind": "board", "company_id": "\(companyID)",
             "company": {"id": "\(companyID)", "name": "Ramp", "stage": "seed"},
             "carousel": {"theme_id": "\(themeID)", "slide_count": 7, "status": "generated",
               "content": [
                 {"type": "cover", "order": 1, "role": "Senior Product Designer", "company": "Ramp",
                  "hook": "design money software people love", "location": "NYC",
                  "compensation": "$150k+", "youd_line": "you'd own the design system",
                  "experience": "senior", "work_mode": "hybrid"},
                 {"type": "about_company", "order": 2, "company": "Ramp",
                  "blurb": "Ramp builds finance automation software.",
                  "industry": "fintech", "stage": "series_d", "backed_by": "Founders Fund"},
                 {"type": "role", "order": 3, "bullets": ["ship the mobile app", "own onboarding"]},
                 {"type": "requirements", "order": 4, "bullets": ["5+ years design", "systems thinking"]},
                 {"type": "perks", "order": 5, "bullets": ["equity", "health cover"]},
                 {"type": "founder", "order": 6, "name": "Jane Doe", "role_title": "CEO"},
                 {"type": "details", "order": 7, "location": "NYC", "employment_type": "Full-time",
                  "compensation": "$150k+"}
               ]}}
            """.data(using: .utf8)!
            let job = try decoder.decode(JobPostingRecord.self, from: json)
            let carousel = try XCTUnwrap(job.carousel)

            let image = render(CarouselFeedCard(
                job: job,
                carousel: carousel,
                safeAreaBottom: 34,
                isActive: false,
                onApply: {},
                onEmailFounder: {},
                onSave: {},
                isSaved: false
            ))
            let unwrapped = try XCTUnwrap(image, "\(archetype) card failed to render")
            XCTAssertGreaterThan(unwrapped.size.width, 300, "\(archetype) rendered too narrow")
            XCTAssertGreaterThan(unwrapped.size.height, 600, "\(archetype) rendered too short")
        }
    }

    func testHeartBurstRenders() throws {
        let image = render(HeartBurstView(trigger: 1), size: CGSize(width: 200, height: 200))
        XCTAssertNotNil(image)
    }

    // The admin Social tab sits behind sign-in, so this is the only
    // automated check that it draws. An unconfigured store (no session
    // provider) must render the empty state rather than trap.
    func testSocialExportViewRendersEmptyState() throws {
        let image = render(SocialExportView(store: SocialExportStore()))
        let unwrapped = try XCTUnwrap(image, "social export view failed to render")
        XCTAssertGreaterThan(unwrapped.size.width, 300)
    }

}
