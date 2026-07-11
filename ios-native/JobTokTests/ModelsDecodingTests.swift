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

    // A slide type this build doesn't recognize is skipped, but the known
    // slides around it still render and the job stays in the feed — a new
    // backend slide type must not drop the job from an old client.
    func testUnknownSlideTypeIsSkippedButKnownSlidesRender() throws {
        let mixed = """
        {
            "theme_id": "slate-gradient",
            "slide_count": 2,
            "status": "generated",
            "content": [
                {"type": "cover", "order": 1, "hook": "Build the feed", "role": "iOS Engineer", "company": "Acme", "location": "NYC"},
                {"type": "hologram", "order": 2}
            ]
        }
        """
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: mixed))
        XCTAssertNotNil(job.carousel)
        XCTAssertEqual(job.carousel?.content.count, 2)          // both decoded
        XCTAssertEqual(job.carousel?.renderableSlides.count, 1) // unknown dropped
        XCTAssertEqual(job.carousel?.hasRenderableSlides, true)
    }

    // A carousel made entirely of unknown slides has nothing to draw, so the
    // feed filter treats it like a missing carousel (hasRenderableSlides false).
    func testAllUnknownSlidesLeaveNothingRenderable() throws {
        let allUnknown = """
        {
            "theme_id": "slate-gradient",
            "slide_count": 1,
            "status": "generated",
            "content": [{"type": "hologram", "order": 1}]
        }
        """
        let job = try decoder.decode(JobPostingRecord.self, from: baseJobJSON(carousel: allUnknown))
        XCTAssertNotNil(job.carousel)
        XCTAssertEqual(job.carousel?.hasRenderableSlides, false)
    }

    // Unknown discriminators decode to .unknown rather than throwing.
    func testUnknownSlideTypeDecodesToUnknownCase() throws {
        let json = #"[{"type": "hologram", "order": 3}]"#.data(using: .utf8)!
        let slides = try decoder.decode([CarouselSlide].self, from: json)
        XCTAssertEqual(slides.count, 1)
        XCTAssertFalse(slides[0].isRenderable)
        XCTAssertEqual(slides[0].order, 3)
    }

    func testCoverSlideDecodesV3Fields() throws {
        let json = """
        [{"type": "cover", "order": 1, "hook": "h", "role": "iOS Engineer",
          "company": "Acme", "location": "NYC", "compensation": "$150k+",
          "youd_line": "you'd own the app end to end",
          "experience": "entry", "work_mode": "remote"}]
        """.data(using: .utf8)!
        let slides = try decoder.decode([CarouselSlide].self, from: json)
        guard case .cover(let s) = slides[0] else { return XCTFail("expected cover") }
        XCTAssertEqual(s.youdLine, "you'd own the app end to end")
        XCTAssertEqual(s.experience, "entry")
        XCTAssertEqual(s.workMode, "remote")
    }

    // v2 covers (no v3 fields) must keep decoding while the catalog regenerates.
    func testCoverSlideDecodesWithoutV3Fields() throws {
        let json = """
        [{"type": "cover", "order": 1, "role": "PM", "company": "Acme"}]
        """.data(using: .utf8)!
        let slides = try decoder.decode([CarouselSlide].self, from: json)
        guard case .cover(let s) = slides[0] else { return XCTFail("expected cover") }
        XCTAssertNil(s.youdLine)
        XCTAssertNil(s.experience)
    }

    func testPerksSlideDecodesAndRenders() throws {
        let json = """
        [{"type": "perks", "order": 5, "bullets": ["Equity", "Health"]}]
        """.data(using: .utf8)!
        let slides = try decoder.decode([CarouselSlide].self, from: json)
        XCTAssertEqual(slides.count, 1)
        XCTAssertTrue(slides[0].isRenderable)
        XCTAssertEqual(slides[0].order, 5)
        if case .perks(let s) = slides[0] {
            XCTAssertEqual(s.bullets, ["Equity", "Health"])
        } else {
            XCTFail("expected .perks")
        }
    }

    func testExperienceAndWorkModeDecode() throws {
        let json = """
        {"id": "j", "title": "t", "is_published": true,
         "created_at": "2026-07-01T12:00:00Z",
         "experience_level": "entry", "work_mode": "remote"}
        """.data(using: .utf8)!
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        XCTAssertEqual(job.experienceLevel, "entry")
        XCTAssertEqual(job.workMode, "remote")
    }

    func testFounderSlideDecodes() throws {
        let json = """
        [{"type": "founder", "order": 6, "name": "Jane Doe", "role_title": "CEO"}]
        """.data(using: .utf8)!
        let slides = try decoder.decode([CarouselSlide].self, from: json)
        XCTAssertTrue(slides[0].isRenderable)
        guard case .founder(let s) = slides[0] else { return XCTFail("expected .founder") }
        XCTAssertEqual(s.name, "Jane Doe")
        XCTAssertEqual(s.roleTitle, "CEO")
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
