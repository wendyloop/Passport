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
            // Selection keys on the company, so the company id is what has
            // to be brute-forced to steer the card onto an archetype. The
            // theme id no longer influences the choice.
            let themeID = "slate-gradient"
            let companyID = try XCTUnwrap(
                (0..<400).map({ "smoke-co-\($0)" }).first {
                    CarouselStyle.resolve(companyKey: $0).archetype == archetype
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


    // MARK: - S-3 cover letter PDF

    func testCoverLetterPDFRendersRealBytes() {
        let data = CoverLetterPDF.render(
            body: "Ramp's spend controls caught my eye.\n\nI built the ledger at Acme.",
            candidateName: "Wendy Shi"
        )
        XCTAssertNotNil(data)
        // %PDF- magic; anything else is not a file an ATS will accept.
        let prefix = data.map { String(decoding: $0.prefix(5), as: UTF8.self) }
        XCTAssertEqual(prefix, "%PDF-")
    }

    func testCoverLetterPDFRefusesEmptyBodies() {
        XCTAssertNil(CoverLetterPDF.render(body: "", candidateName: "Wendy Shi"))
        XCTAssertNil(CoverLetterPDF.render(body: "   \n  ", candidateName: nil))
    }

    // A long letter must paginate rather than silently clip at one page.
    func testCoverLetterPDFPaginatesLongBodies() {
        let long = String(repeating: "This is a sentence about the role. ", count: 400)
        let data = CoverLetterPDF.render(body: long, candidateName: "Wendy Shi")
        XCTAssertNotNil(data)
        let short = CoverLetterPDF.render(body: "One line.", candidateName: "Wendy Shi")
        XCTAssertGreaterThan(data?.count ?? 0, short?.count ?? 0)
    }

    func testCoverLetterFileNameIsUploaderSafe() {
        XCTAssertEqual(
            CoverLetterPDF.fileName(candidateName: "Wendy Shi", companyName: "Ramp"),
            "Wendy_Shi_Ramp_Cover_Letter.pdf"
        )
        // Punctuation some uploaders reject outright.
        XCTAssertEqual(
            CoverLetterPDF.fileName(candidateName: "O'Brien-Smith", companyName: "A&B, Inc."),
            "OBrienSmith_AB_Inc_Cover_Letter.pdf"
        )
        XCTAssertEqual(
            CoverLetterPDF.fileName(candidateName: nil, companyName: nil),
            "Cover_Letter.pdf"
        )
    }

    // MARK: - S-4 resume PDF

    private func sampleResumeContent(bullets: Int = 3) -> ResumePDF.Content {
        ResumePDF.Content(
            fullName: "Wendy Shi",
            contactLine: "wendy@example.com · San Francisco, CA",
            summary: "Engineer who ships payments infrastructure.",
            roles: [
                ResumePDF.Content.Role(
                    company: "Acme",
                    title: "Software Engineer",
                    dates: "2024-01 – Present",
                    bullets: (0..<bullets).map { "Built the ledger service, cutting p99 by \($0)0%" }
                )
            ],
            education: [
                ResumePDF.Content.School(school: "UCLA", degree: "BS", year: "2023")
            ],
            skills: ["Go", "PostgreSQL", "Kubernetes"]
        )
    }

    func testResumePDFRendersRealBytes() {
        let data = ResumePDF.render(sampleResumeContent())
        XCTAssertNotNil(data)
        let prefix = data.map { String(decoding: $0.prefix(5), as: UTF8.self) }
        XCTAssertEqual(prefix, "%PDF-")
    }

    func testResumePDFRefusesAnEmptyResume() {
        let empty = ResumePDF.Content(
            fullName: "  ", contactLine: "", summary: nil,
            roles: [], education: [], skills: []
        )
        XCTAssertNil(ResumePDF.render(empty))
    }

    // A resume with a long history must paginate, not clip. Silently dropping
    // someone's earlier roles is the worst possible failure here.
    func testResumePDFPaginatesLongHistories() {
        let short = ResumePDF.render(sampleResumeContent(bullets: 2))
        let long = ResumePDF.render(sampleResumeContent(bullets: 120))
        XCTAssertNotNil(long)
        XCTAssertGreaterThan(long?.count ?? 0, short?.count ?? 0)
    }

    func testResumePDFRendersFromATailoredVersion() throws {
        let json = """
        {"summary":"Payments engineer.","skills_ordered":["Go","Kafka"],
         "employment":[{"company":"Acme","title":"SWE","dates":"2024 – Present",
           "bullets":[{"key":"a1","original":"Built the ledger",
                       "tailored":"Built the ledger service in Go",
                       "keywords_added":["Go"]}]}],
         "keywords_covered":["Go"],"keywords_still_missing":["Kafka"]}
        """.data(using: .utf8)!
        let tailored = try JSONDecoder().decode(TailoredResumeContent.self, from: json)
        XCTAssertEqual(tailored.changedBullets.count, 1)

        let content = ResumePDF.Content(
            tailored: tailored,
            fullName: "Wendy Shi",
            contactLine: "wendy@example.com",
            education: [ParsedResumeDetails.Education(
                school: "UCLA", degree: "BS", fieldOfStudy: "CS", graduationYear: "2023"
            )]
        )
        // The PDF must carry the TAILORED wording, not the original.
        XCTAssertEqual(content.roles.first?.bullets.first, "Built the ledger service in Go")
        XCTAssertEqual(content.education.first?.school, "UCLA")
        XCTAssertNotNil(ResumePDF.render(content))
    }

    func testTailoredBulletChangeDetectionIgnoresWhitespace() throws {
        let json = """
        {"key":"a1","original":"  Built the ledger  ","tailored":"Built the ledger",
         "keywords_added":[]}
        """.data(using: .utf8)!
        let bullet = try JSONDecoder().decode(TailoredResumeContent.Bullet.self, from: json)
        // Same sentence, different padding: not a change worth showing.
        XCTAssertFalse(bullet.wasChanged)
    }

    func testResumeFileNameIsUploaderSafe() {
        XCTAssertEqual(
            ResumePDF.fileName(candidateName: "Wendy Shi", companyName: "Ramp"),
            "Wendy_Shi_Ramp_Resume.pdf"
        )
        XCTAssertEqual(
            ResumePDF.fileName(candidateName: nil, companyName: nil),
            "Resume.pdf"
        )
    }
}
