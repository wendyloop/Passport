import XCTest
import SwiftUI
@testable import JobTok

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

    func testHeartBurstRenders() throws {
        let image = render(HeartBurstView(trigger: 1), size: CGSize(width: 200, height: 200))
        XCTAssertNotNil(image)
    }
}
