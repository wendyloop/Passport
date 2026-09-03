import XCTest
@testable import scout22

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

    // AUDIT P1-9: employer fetches embed application_notes(notes) from the
    // employer-only table; candidate fetches (plain select=*) have no such
    // key. Both shapes must decode.
    private func applicationJSON(extraField: String) -> Data {
        """
        {
            "id": "app-1",
            "job_id": "job-1",
            "employer_profile_id": "emp-1",
            "candidate_profile_id": "cand-1",
            "status": "submitted",
            "job_title": "iOS Engineer",
            "company_name": "Acme",
            "application_email": "jobs@acme.io",
            "candidate_name": "Sam Seeker",
            "candidate_previous_employers": [],
            "email_delivery_status": "sent",
            "applied_at": "2026-07-01T12:00:00Z"\(extraField)
        }
        """.data(using: .utf8)!
    }

    func testApplicationDecodesEmbeddedEmployerNotes() throws {
        let json = applicationJSON(extraField: #", "application_notes": {"notes": "strong portfolio"}"#)
        let application = try decoder.decode(JobApplicationRecord.self, from: json)
        XCTAssertEqual(application.internalNotes, "strong portfolio")
    }

    func testApplicationDecodesNullNotesEmbed() throws {
        let json = applicationJSON(extraField: #", "application_notes": null"#)
        let application = try decoder.decode(JobApplicationRecord.self, from: json)
        XCTAssertNil(application.internalNotes)
    }

    func testApplicationDecodesWithoutNotesEmbed() throws {
        let application = try decoder.decode(JobApplicationRecord.self, from: applicationJSON(extraField: ""))
        XCTAssertNil(application.internalNotes)
    }

    // MARK: - S-5 multiple resumes

    func testResumeDecodesS5ColumnsAndDefaultsWithoutThem() throws {
        let withColumns = """
        {"id":"r1","profile_id":"p1","file_path":"p1/swe.pdf","parse_status":"parsed",
         "parsed_employers":[],"created_at":"2026-09-01T00:00:00Z",
         "is_default":true,"label":"SWE resume"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let a = try decoder.decode(ResumeUploadRecord.self, from: withColumns)
        XCTAssertTrue(a.isDefault)
        XCTAssertEqual(a.label, "SWE resume")
        XCTAssertEqual(a.displayName, "SWE resume")

        // A query that does not select the S-5 columns must still decode —
        // several call sites ask for a narrower column list.
        let without = """
        {"id":"r2","profile_id":"p1","file_path":"p1/old.pdf","parse_status":"parsed",
         "parsed_employers":[],"created_at":"2026-08-01T00:00:00Z"}
        """.data(using: .utf8)!
        let b = try decoder.decode(ResumeUploadRecord.self, from: without)
        XCTAssertFalse(b.isDefault)
        XCTAssertNil(b.label)
        // Falls back to the file name so a picker row is never blank.
        XCTAssertEqual(b.displayName, "old.pdf")
    }

    func testResumeDisplayNameIgnoresBlankLabels() throws {
        let json = """
        {"id":"r3","profile_id":"p1","file_path":"p1/a/b/cv.pdf","parse_status":"parsed",
         "parsed_employers":[],"created_at":"2026-08-01T00:00:00Z","label":"   "}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let r = try decoder.decode(ResumeUploadRecord.self, from: json)
        XCTAssertEqual(r.displayName, "cv.pdf")
    }

    // MARK: - S-4 resume bullets

    func testEmployerBulletsRoundTripAndDefaultWhenAbsent() throws {
        let decoder = JSONDecoder()
        let withBullets = """
        {"current_title":"Engineer","skills":[],"education":[],
         "employers":[{"company":"Acme","title":"SWE","start_date":"2024-01",
         "end_date":"","is_current":true,
         "bullets":["Built the ledger","Cut p99 by 40%"]}]}
        """.data(using: .utf8)!
        let a = try decoder.decode(ParsedResumeDetails.self, from: withBullets)
        XCTAssertEqual(a.employers.first?.bullets, ["Built the ledger", "Cut p99 by 40%"])

        // Every resume parsed before S-4 has no bullets key at all; those must
        // decode rather than throwing, and re-parse from stored text later.
        let legacy = """
        {"current_title":"Engineer","skills":[],"education":[],
         "employers":[{"company":"Acme","title":"SWE","start_date":"2024-01",
         "end_date":"","is_current":true}]}
        """.data(using: .utf8)!
        let b = try decoder.decode(ParsedResumeDetails.self, from: legacy)
        XCTAssertEqual(b.employers.first?.bullets, [])

        // Round trip: encoding must carry bullets back out, or the profile
        // editor's save erases them.
        let reencoded = try JSONEncoder().encode(a)
        let c = try decoder.decode(ParsedResumeDetails.self, from: reencoded)
        XCTAssertEqual(c.employers.first?.bullets, ["Built the ledger", "Cut p99 by 40%"])
    }
}
