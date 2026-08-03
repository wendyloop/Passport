import XCTest
@testable import scout22

final class SharedFormattersTests: XCTestCase {
    func testAnnualRange() {
        XCTAssertEqual(
            SharedFormatters.compensation(min: 120_000, max: 150_000, suffix: ""),
            "$120,000 – $150,000"
        )
    }

    func testHourlyMinOnly() {
        XCTAssertEqual(
            SharedFormatters.compensation(min: 30, max: nil, suffix: "/hr"),
            "From $30/hr"
        )
    }

    func testMaxOnly() {
        XCTAssertEqual(
            SharedFormatters.compensation(min: nil, max: 90_000, suffix: ""),
            "Up to $90,000"
        )
    }

    func testNilBothIsNil() {
        XCTAssertNil(SharedFormatters.compensation(min: nil, max: nil, suffix: ""))
    }

    func testProfileHandleStripsAndLowercases() {
        XCTAssertEqual(SharedFormatters.profileHandle("  @Wendy-Loop! "), "wendyloop")
        XCTAssertEqual(SharedFormatters.profileHandle("under_score9"), "under_score9")
        XCTAssertEqual(SharedFormatters.profileHandle("🎉🎉"), "")
    }

    func testDurationFormatting() {
        XCTAssertEqual(SharedFormatters.duration(0), "0:00")
        XCTAssertEqual(SharedFormatters.duration(65), "1:05")
        XCTAssertEqual(SharedFormatters.duration(59.6), "1:00")
    }

    func testRelativeAge() {
        let now = ISO8601DateFormatter().date(from: "2026-07-09T12:00:00Z")!
        func age(_ iso: String) -> String {
            SharedFormatters.relativeAge(of: ISO8601DateFormatter().date(from: iso)!, now: now)
        }
        XCTAssertEqual(age("2026-07-09T08:00:00Z"), "today")
        XCTAssertEqual(age("2026-07-08T08:00:00Z"), "1d ago")
        XCTAssertEqual(age("2026-07-04T08:00:00Z"), "5d ago")
        XCTAssertEqual(age("2026-06-20T08:00:00Z"), "2w ago")
    }

    func testFounderPitchGating() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(stage: String?, contactable: Bool?) throws -> JobPostingRecord {
            let stageJSON = stage.map { "\"\($0)\"" } ?? "null"
            let contactableJSON = contactable.map { "\($0)" } ?? "null"
            let json = """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z", "company_id": "co-1",
             "company": {"id": "co-1", "name": "Acme", "stage": \(stageJSON),
                         "founder_contactable": \(contactableJSON)}}
            """.data(using: .utf8)!
            return try decoder.decode(JobPostingRecord.self, from: json)
        }
        // Startup stages with a contact on file → pitchable.
        XCTAssertTrue(try job(stage: "seed", contactable: true).founderPitchAllowed)
        XCTAssertTrue(try job(stage: nil, contactable: true).founderPitchAllowed)
        XCTAssertTrue(try job(stage: "series_b", contactable: true).founderPitchAllowed)
        // No usable contact (false or column absent) → never pitchable.
        XCTAssertFalse(try job(stage: "seed", contactable: false).founderPitchAllowed)
        XCTAssertFalse(try job(stage: "seed", contactable: nil).founderPitchAllowed)
        // Big-company stages stay apply-only even with a contact.
        XCTAssertFalse(try job(stage: "1000+ employees", contactable: true).founderPitchAllowed)
        XCTAssertFalse(try job(stage: "acquisition", contactable: true).founderPitchAllowed)
        XCTAssertFalse(try job(stage: "ipo", contactable: true).founderPitchAllowed)

        // No company embed at all → not pitchable.
        let bare = try decoder.decode(
            JobPostingRecord.self,
            from: """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z"}
            """.data(using: .utf8)!
        )
        XCTAssertFalse(bare.founderPitchAllowed)
    }

    func testCompanySizeFilterMatching() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(sizeBucket: String?) throws -> JobPostingRecord {
            let bucketJSON = sizeBucket.map { "\"\($0)\"" } ?? "null"
            let json = """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z", "company_id": "co-1",
             "company": {"id": "co-1", "name": "Acme", "size_bucket": \(bucketJSON)}}
            """.data(using: .utf8)!
            return try decoder.decode(JobPostingRecord.self, from: json)
        }

        XCTAssertTrue(try CompanySizeFilter.all.matches(job(sizeBucket: nil)))
        XCTAssertTrue(try CompanySizeFilter.under10.matches(job(sizeBucket: "under_10")))
        XCTAssertTrue(try CompanySizeFilter.over1000.matches(job(sizeBucket: "1000_plus")))
        XCTAssertFalse(try CompanySizeFilter.under10.matches(job(sizeBucket: "10_100")))
        // Unknown-size companies only appear under "All".
        XCTAssertFalse(try CompanySizeFilter.under10.matches(job(sizeBucket: nil)))

        // Raw values ARE the server bucket strings the PostgREST param uses.
        XCTAssertNil(CompanySizeFilter.all.bucketValue)
        XCTAssertEqual(CompanySizeFilter.from10To100.bucketValue, "10_100")
        XCTAssertEqual(CompanySizeFilter.from100To1000.bucketValue, "100_1000")
    }

    func testProfileStrengthWeights() {
        var draft = CandidateProfileDraft()
        XCTAssertEqual(ProfileStrength.score(for: draft), 0)
        XCTAssertEqual(ProfileStrength.missing(for: draft).count, 6)

        draft.resumeStoragePath = "me/resume.pdf"
        XCTAssertEqual(ProfileStrength.score(for: draft), 30)
        draft.introVideoURL = "https://cdn/videos/me.mp4"
        XCTAssertEqual(ProfileStrength.score(for: draft), 60)
        draft.avatarURL = "https://cdn/avatars/me.jpg"
        draft.headline = "CS @ Berkeley"
        XCTAssertEqual(ProfileStrength.score(for: draft), 75)
        draft.githubURL = "github.com/me"
        XCTAssertEqual(ProfileStrength.score(for: draft), 90)
        draft.school = "UC Berkeley"
        XCTAssertEqual(ProfileStrength.score(for: draft), 100)
        XCTAssertTrue(ProfileStrength.missing(for: draft).isEmpty)

        // Whitespace-only values don't count.
        draft.githubURL = "   "
        draft.headline = " "
        XCTAssertEqual(ProfileStrength.score(for: draft), 78)
    }

    func testMatchFitBuckets() {
        XCTAssertEqual(MatchFit.bucket(for: nil), 2)
        XCTAssertEqual(MatchFit.bucket(for: 100), 0)
        XCTAssertEqual(MatchFit.bucket(for: 70), 0)
        XCTAssertEqual(MatchFit.bucket(for: 69), 1)
        XCTAssertEqual(MatchFit.bucket(for: 50), 1)
        XCTAssertEqual(MatchFit.bucket(for: 49), 2)
        XCTAssertEqual(MatchFit.bucket(for: 0), 2)
    }

    func testFeedRankFitBucketOrdersAheadOfAffinityAndComp() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(_ id: String, comp: Bool) throws -> JobPostingRecord {
            let compJSON = comp ? "120000" : "null"
            return try decoder.decode(JobPostingRecord.self, from: """
            {"id": "\(id)", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z",
             "compensation_min_annual": \(compJSON)}
            """.data(using: .utf8)!)
        }
        let now = Date()
        // Great fit without comp beats neutral fit with comp.
        let greatFitNoComp = try job("a", comp: false).feedRank(now: now, affinity: [], fitBucket: 0)
        let neutralFitComp = try job("b", comp: true).feedRank(now: now, affinity: [], fitBucket: 2)
        XCTAssertTrue(greatFitNoComp < neutralFitComp)
        // Default fitBucket is neutral — ranking identical to the old tuple.
        let defaulted = try job("c", comp: true).feedRank(now: now, affinity: [])
        XCTAssertEqual(defaulted.2, 2)
    }

    func testSavedJobsOrdering() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(_ id: String) throws -> JobPostingRecord {
            try decoder.decode(JobPostingRecord.self, from: """
            {"id": "\(id)", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z"}
            """.data(using: .utf8)!)
        }
        func saved(_ jobID: String, at iso: String) -> SavedJobRecord {
            SavedJobRecord(
                id: "s-\(jobID)", profileID: "me", jobID: jobID,
                createdAt: ISO8601DateFormatter().date(from: iso)!
            )
        }
        func application(_ jobID: String, at iso: String) throws -> JobApplicationRecord {
            try decoder.decode(JobApplicationRecord.self, from: """
            {"id": "a-\(jobID)", "job_id": "\(jobID)", "employer_profile_id": "e",
             "candidate_profile_id": "me", "status": "submitted", "job_title": "t",
             "company_name": "c", "application_email": "x@y.z", "candidate_name": "n",
             "candidate_previous_employers": [], "email_delivery_status": "sent",
             "applied_at": "\(iso)"}
            """.data(using: .utf8)!)
        }

        // Saved order (newest first): j3, j2, j1, j4. Applied: j3 (older
        // application) and j1 (newer application). Expect: unapplied j2, j4
        // by save recency, then applied j1, j3 by application recency.
        let jobs = Dictionary(uniqueKeysWithValues: try ["j1", "j2", "j3", "j4"].map { ($0, try job($0)) })
        let records = [
            saved("j3", at: "2026-07-20T10:00:00Z"),
            saved("j2", at: "2026-07-18T10:00:00Z"),
            saved("j1", at: "2026-07-15T10:00:00Z"),
            saved("j4", at: "2026-07-10T10:00:00Z"),
        ]
        let applications = [
            try application("j3", at: "2026-07-21T09:00:00Z"),
            try application("j1", at: "2026-07-22T09:00:00Z"),
        ]
        let ordered = SavedJobsOrdering.ordered(records: records, applications: applications, jobs: jobs)
        XCTAssertEqual(ordered.map(\.id), ["j2", "j4", "j1", "j3"])

        // A saved job missing from the lookup is dropped, not crashed on.
        let partial = SavedJobsOrdering.ordered(
            records: records, applications: [],
            jobs: jobs.filter { $0.key != "j2" }
        )
        XCTAssertEqual(partial.map(\.id), ["j3", "j1", "j4"])
    }

    func testFounderFatigueBuckets() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(touch: String?) throws -> JobPostingRecord {
            let touchJSON = touch.map { "\"\($0)\"" } ?? "null"
            let json = """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z",
             "last_founder_touch_at": \(touchJSON)}
            """.data(using: .utf8)!
            return try decoder.decode(JobPostingRecord.self, from: json)
        }
        let now = ISO8601DateFormatter().date(from: "2026-07-08T15:00:00Z")!
        XCTAssertEqual(try job(touch: nil).founderFatigueBucket(now: now), 0)
        XCTAssertEqual(try job(touch: "2026-07-08T09:00:00Z").founderFatigueBucket(now: now), 2)
        XCTAssertEqual(try job(touch: "2026-07-05T09:00:00Z").founderFatigueBucket(now: now), 1)
        XCTAssertEqual(try job(touch: "2026-06-20T09:00:00Z").founderFatigueBucket(now: now), 0)
    }

    // FIRST-100-USERS: pitching one role must cool every role at that company
    // for the week — one founder, several openings, one inbox.
    func testCompanyFounderTouchDemotesSiblingRoles() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(jobTouch: String?, companyTouch: String?) throws -> JobPostingRecord {
            let j = jobTouch.map { "\"\($0)\"" } ?? "null"
            let c = companyTouch.map { "\"\($0)\"" } ?? "null"
            let json = """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z",
             "last_founder_touch_at": \(j),
             "company_id": "co-1",
             "company": {"id": "co-1", "name": "Acme", "last_founder_touch_at": \(c)}}
            """.data(using: .utf8)!
            return try decoder.decode(JobPostingRecord.self, from: json)
        }
        let now = ISO8601DateFormatter().date(from: "2026-07-08T15:00:00Z")!

        // The sibling role itself was never pitched, but its company was.
        XCTAssertEqual(try job(jobTouch: nil, companyTouch: "2026-07-08T09:00:00Z").founderFatigueBucket(now: now), 2)
        XCTAssertEqual(try job(jobTouch: nil, companyTouch: "2026-07-05T09:00:00Z").founderFatigueBucket(now: now), 1)
        // Older than the week: back to full priority.
        XCTAssertEqual(try job(jobTouch: nil, companyTouch: "2026-06-20T09:00:00Z").founderFatigueBucket(now: now), 0)
        // Neither touched.
        XCTAssertEqual(try job(jobTouch: nil, companyTouch: nil).founderFatigueBucket(now: now), 0)
        // The more recent of the two wins, whichever side it came from.
        XCTAssertEqual(
            try job(jobTouch: "2026-07-05T09:00:00Z", companyTouch: "2026-07-08T09:00:00Z").founderFatigueBucket(now: now), 2)
        XCTAssertEqual(
            try job(jobTouch: "2026-07-08T09:00:00Z", companyTouch: "2026-07-05T09:00:00Z").founderFatigueBucket(now: now), 2)
        // Job-level fallback still works when no company is embedded.
        XCTAssertEqual(try job(jobTouch: "2026-07-05T09:00:00Z", companyTouch: nil).founderFatigueBucket(now: now), 1)
    }

    // A founder pitch writes a job_applications row with a null employer and
    // null application_email; both were non-optional until now, so this is the
    // decode that would have taken down the whole Applications page.
    func testFounderPitchApplicationDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "a1", "job_id": "j1", "employer_profile_id": null,
         "candidate_profile_id": "c1", "status": "submitted",
         "job_title": "Founding Designer", "company_name": "Acme",
         "application_email": null, "candidate_name": "Wendy",
         "candidate_previous_employers": [],
         "email_delivery_status": "sent",
         "applied_at": "2026-08-01T12:00:00Z",
         "application_kind": "founder_pitch",
         "founder_pitched_at": "2026-08-01T12:00:00Z"}
        """.data(using: .utf8)!
        let application = try decoder.decode(JobApplicationRecord.self, from: json)
        XCTAssertNil(application.employerProfileID)
        XCTAssertNil(application.applicationEmail)
        XCTAssertTrue(application.isFounderPitch)
        XCTAssertTrue(application.didPitchFounder)
    }

    // A pitch upgraded by a later ATS apply reads as a normal application but
    // keeps the pitch history.
    func testUpgradedApplicationReadsAsApplyButKeepsPitchHistory() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "a2", "job_id": "j1", "employer_profile_id": null,
         "candidate_profile_id": "c1", "status": "submitted",
         "job_title": "Founding Designer", "company_name": "Acme",
         "application_email": "jobs@acme.io", "candidate_name": "Wendy",
         "candidate_previous_employers": [],
         "email_delivery_status": "sent",
         "applied_at": "2026-08-01T12:00:00Z",
         "application_kind": "ats_apply",
         "founder_pitched_at": "2026-07-30T12:00:00Z"}
        """.data(using: .utf8)!
        let application = try decoder.decode(JobApplicationRecord.self, from: json)
        XCTAssertFalse(application.isFounderPitch)
        XCTAssertTrue(application.didPitchFounder)
    }

    // Rows cached before the columns existed must still decode as ordinary
    // applications.
    func testApplicationWithoutKindColumnsDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"id": "a3", "job_id": "j1", "employer_profile_id": "e1",
         "candidate_profile_id": "c1", "status": "submitted",
         "job_title": "Designer", "company_name": "Acme",
         "application_email": "jobs@acme.io", "candidate_name": "Wendy",
         "candidate_previous_employers": [],
         "email_delivery_status": "sent",
         "applied_at": "2026-08-01T12:00:00Z"}
        """.data(using: .utf8)!
        let application = try decoder.decode(JobApplicationRecord.self, from: json)
        XCTAssertFalse(application.isFounderPitch)
        XCTAssertFalse(application.didPitchFounder)
    }

    func testCompensationSummaryPrefersAnnual() throws {
        let json = """
        {
            "id": "j", "title": "t", "is_published": true,
            "created_at": "2026-07-01T12:00:00Z",
            "compensation_min_annual": 100000,
            "compensation_min_hourly": 50
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let job = try decoder.decode(JobPostingRecord.self, from: json)
        XCTAssertEqual(job.compensationSummary, "From $100,000")
    }
}
