import XCTest
import SwiftUI
@testable import scout22

@MainActor
final class SocialCardExporterTests: XCTestCase {

    // MARK: - Fixtures

    /// Carousel with every slide type, including a founder slide.
    private func job(withFounder: Bool = true, slides extra: String = "") throws -> JobPostingRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let founder = withFounder
            ? #"{"type": "founder", "order": 5, "name": "Jane Doe", "role_title": "CEO"},"#
            : ""
        let json = """
        {"id": "job-social-1", "title": "Senior Product Designer", "company_name": "Ramp",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board", "company_id": "co-1", "location": "NYC",
         "compensation_text": "$150k+",
         "company": {"id": "co-1", "name": "Ramp", "stage": "seed"},
         "carousel": {"theme_id": "sunset-paper", "slide_count": 6, "status": "generated",
           "content": [
             {"type": "cover", "order": 1, "role": "Senior Product Designer", "company": "Ramp",
              "hook": "design money software people love",
              "youd_line": "you'd own the design system",
              "location": "NYC", "compensation": "$150k+"},
             {"type": "about_company", "order": 2, "company": "Ramp",
              "blurb": "Ramp builds finance automation software."},
             {"type": "role", "order": 3, "bullets": ["ship the mobile app"]},
             {"type": "requirements", "order": 4, "bullets": ["5+ years design"]},
             \(founder)
             {"type": "details", "order": 6, "location": "NYC",
              "employment_type": "Full-time", "compensation": "$150k+"}\(extra)
           ]}}
        """.data(using: .utf8)!
        return try decoder.decode(JobPostingRecord.self, from: json)
    }

    // MARK: - Founder exclusion

    /// The founder slide names a real person pulled from a JD or a contact
    /// scrape. In-app exposure to one job seeker is not consent to appear on
    /// a public Instagram grid, and this filter is the only thing between
    /// that data and a published image file.
    func testFounderSlideIsNeverPublishable() throws {
        let job = try job(withFounder: true)
        let carousel = try XCTUnwrap(job.carousel)

        // Present in what the app renders...
        XCTAssertTrue(carousel.renderableSlides.contains { slide in
            if case .founder = slide { return true }
            return false
        }, "fixture should contain a founder slide")

        // ...and absent from what gets exported.
        let publishable = SocialCardExporter.publishableSlides(carousel, job: job)
        XCTAssertFalse(publishable.contains { slide in
            if case .founder = slide { return true }
            return false
        }, "founder slide must never reach an exported image")
    }

    func testFounderExclusionDoesNotDropOtherSlides() throws {
        let withFounder = try job(withFounder: true)
        let without = try job(withFounder: false)
        let a = SocialCardExporter.publishableSlides(try XCTUnwrap(withFounder.carousel), job: withFounder)
        let b = SocialCardExporter.publishableSlides(try XCTUnwrap(without.carousel), job: without)
        XCTAssertEqual(a.count, b.count, "only the founder slide should differ")
    }

    // MARK: - Slide selection

    func testEmptyDetailsSlideIsExcluded() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // No location/comp on either the job or the details slide.
        let json = """
        {"id": "job-bare", "title": "Designer", "company_name": "Acme",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board", "company_id": "co-1",
         "carousel": {"theme_id": "slate-gradient", "slide_count": 3, "status": "generated",
           "content": [
             {"type": "cover", "order": 1, "role": "Designer", "company": "Acme"},
             {"type": "role", "order": 2, "bullets": ["design things"]},
             {"type": "details", "order": 3}
           ]}}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        let slides = SocialCardExporter.publishableSlides(try XCTUnwrap(job.carousel), job: job)
        XCTAssertFalse(slides.contains { slide in
            if case .details = slide { return true }
            return false
        })
    }

    func testSlideCountIsCappedForPlatformLimits() throws {
        // Instagram accepts at most 10 images per carousel.
        let many = (7...20).map { #"{"type": "role", "order": \#($0), "bullets": ["x"]}"# }
        let job = try job(withFounder: true, slides: "," + many.joined(separator: ","))
        let slides = SocialCardExporter.publishableSlides(try XCTUnwrap(job.carousel), job: job)
        XCTAssertLessThanOrEqual(slides.count, SocialCardExporter.maxSlides)
    }

    func testTooFewSlidesThrowsRatherThanPostingAStub() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "job-thin", "title": "Designer", "company_name": "Acme",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board", "company_id": "co-1",
         "carousel": {"theme_id": "slate-gradient", "slide_count": 3, "status": "generated",
           "content": [
             {"type": "cover", "order": 1, "role": "Designer", "company": "Acme"},
             {"type": "founder", "order": 2, "name": "Jane Doe"},
             {"type": "details", "order": 3}
           ]}}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        let carousel = try XCTUnwrap(job.carousel)
        XCTAssertThrowsError(try SocialCardExporter.renderJPEGs(job: job, carousel: carousel)) { error in
            guard case SocialCardExporter.ExportError.tooFewSlides = error else {
                return XCTFail("expected tooFewSlides, got \(error)")
            }
        }
    }

    // MARK: - Rendering

    /// Instagram's native 4:5 feed size. The design canvas is 390×487.5, so
    /// scale 1080/390 must land exactly on 1080×1350 with no cropping.
    func testRendersAtInstagramNativeSize() throws {
        let job = try job()
        let carousel = try XCTUnwrap(job.carousel)
        let jpegs = try SocialCardExporter.renderJPEGs(job: job, carousel: carousel)

        XCTAssertGreaterThanOrEqual(jpegs.count, SocialCardExporter.minSlides)
        for (index, data) in jpegs.enumerated() {
            let image = try XCTUnwrap(UIImage(data: data), "slide \(index) is not decodable")
            // UIImage.size is in points; pixels are size × scale.
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            XCTAssertEqual(pixelWidth, 1080, accuracy: 1, "slide \(index) width")
            XCTAssertEqual(pixelHeight, 1350, accuracy: 1, "slide \(index) height")
            // Meta rejects images over 8MB.
            XCTAssertLessThan(data.count, 8 * 1024 * 1024, "slide \(index) too large")
        }
    }

    // MARK: - Caption

    /// `hook` and `youd_line` are generated for every job and rendered by no
    /// template — the caption is the one place they're consumed.
    func testCaptionLeadsWithTheHook() throws {
        let job = try job()
        let carousel = try XCTUnwrap(job.carousel)
        let caption = SocialCardExporter.caption(job: job, carousel: carousel)
        XCTAssertTrue(caption.hasPrefix("design money software people love"))
        XCTAssertTrue(caption.contains("Ramp"))
        XCTAssertTrue(caption.contains("$150k+"))
        XCTAssertTrue(caption.contains("link in bio"))
    }

    func testCaptionFallsBackToYoudLineWhenHookIsEmpty() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "job-nohook", "title": "Designer", "company_name": "Acme",
         "is_published": true, "created_at": "2026-07-01T12:00:00Z",
         "source_kind": "board", "company_id": "co-1", "location": "NYC",
         "carousel": {"theme_id": "slate-gradient", "slide_count": 3, "status": "generated",
           "content": [
             {"type": "cover", "order": 1, "role": "Designer", "company": "Acme",
              "hook": "", "youd_line": "you'd redesign onboarding"},
             {"type": "role", "order": 2, "bullets": ["design things"]},
             {"type": "details", "order": 3, "location": "NYC"}
           ]}}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        let caption = SocialCardExporter.caption(job: job, carousel: try XCTUnwrap(job.carousel))
        XCTAssertTrue(caption.hasPrefix("you'd redesign onboarding"))
    }

    func testHashtagsStayUnderInstagramLimit() throws {
        let job = try job()
        let tags = SocialCardExporter.hashtags(job: job)
        XCTAssertLessThanOrEqual(tags.count, 30)
        XCTAssertTrue(tags.contains("scout22"))
        // No leading '#' — the caller renders them.
        XCTAssertFalse(tags.contains { $0.hasPrefix("#") })
    }

    func testStoragePathIsPlatformScoped() {
        let path = SocialCardExporter.storagePath(jobID: "abc", platform: .instagram, index: 2)
        XCTAssertEqual(path, "abc/instagram/2.jpg")
    }
}
