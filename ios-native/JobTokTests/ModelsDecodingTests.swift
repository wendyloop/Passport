import XCTest
@testable import JobTok

final class ModelsDecodingTests: XCTestCase {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func baseJobJSON(carousel: String) -> Data {
        """
        {
            "id": "job-1",
            "title": "iOS Engineer",
            "company_name": "Acme",
            "is_published": true,
            "created_at": "2026-07-01T12:00:00Z",
            "source_kind": "board",
            "company_id": "co-1",
            "carousel": \(carousel)
        }
        """.data(using: .utf8)!
    }

    private let carouselObject = """
    {
        "theme_id": "slate-gradient",
        "slide_count": 3,
        "status": "generated",
        "content": [
            {"type": "cover", "order": 1, "hook": "Build the feed", "role": "iOS Engineer", "company": "Acme", "location": "NYC"},
            {"type": "about_company", "order": 2, "blurb": "Acme makes widgets."},
            {"type": "details", "order": 3, "location": "NYC", "compensation": null, "employment_type": null, "apply_hint": null}
        ]
    }
    """

    // PostgREST embeds a one-to-one FK as either a single object or a
    // 1-element array depending on constraint discovery — the hand-written
    // init must accept both.
    func testJobDecodesCarouselAsObject() throws {
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: carouselObject))
        XCTAssertEqual(job.carousel?.themeId, "slate-gradient")
        XCTAssertEqual(job.carousel?.content.count, 3)
    }

    func testJobDecodesCarouselAsSingleElementArray() throws {
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: "[\(carouselObject)]"))
        XCTAssertEqual(job.carousel?.themeId, "slate-gradient")
        XCTAssertEqual(job.carousel?.slideCount, 3)
    }

    func testJobDecodesNullCarousel() throws {
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: "null"))
        XCTAssertNil(job.carousel)
    }

    func testUnknownSourceKindishDefaultsSafely() throws {
        // Absent source_kind must fall back to the legacy employer_post.
        let json = """
        {"id": "job-2", "title": "PM", "is_published": false, "created_at": "2026-07-01T12:00:00Z"}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        XCTAssertEqual(job.sourceKind, .employerPost)
    }

    // The job-level decode deliberately swallows a malformed carousel
    // (try? in the hand-written init) so one bad slide can't take down the
    // entire feed response — the job survives with carousel == nil.
    func testUnknownSlideTypeDropsCarouselButKeepsJob() throws {
        let badSlide = """
        {
            "theme_id": "slate-gradient",
            "slide_count": 1,
            "status": "generated",
            "content": [{"type": "hologram", "order": 1}]
        }
        """
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: badSlide))
        XCTAssertNil(job.carousel)
        XCTAssertEqual(job.id, "job-1")
    }

    // The slide enum itself is strict — unknown discriminators throw.
    func testUnknownSlideTypeThrowsAtSlideLevel() {
        let json = #"[{"type": "hologram", "order": 1}]"#.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode([CarouselSlide].self, from: json))
    }

    func testFounderEmailPreviewDecodes() throws {
        let json = """
        {
            "eligible": true,
            "reason": null,
            "contact": {
                "id": "c-1",
                "fullName": "Jane Doe",
                "roleTitle": "CEO",
                "emailMasked": "j•••@acme.io",
                "source": "llm_scrape",
                "confidence": 0.9
            },
            "remaining": 4,
            "limit": 5,
            "subjectPreview": "Intro from Sam — iOS Engineer"
        }
        """.data(using: .utf8)!
        let preview = try decoder.decode(FounderEmailPreview.self, from: json)
        XCTAssertTrue(preview.eligible)
        XCTAssertEqual(preview.contact?.emailMasked, "j•••@acme.io")
        XCTAssertTrue(preview.contact?.isGuessedAddress == true)
        XCTAssertEqual(preview.remaining, 4)
    }

    func testPostingEmailContactIsNotGuessed() throws {
        let json = """
        {"id": "c-2", "fullName": null, "roleTitle": null, "emailMasked": "h•••@acme.io", "source": "posting_email", "confidence": null}
        """.data(using: .utf8)!
        let contact = try decoder.decode(FounderContactPreview.self, from: json)
        XCTAssertFalse(contact.isGuessedAddress)
    }
}
