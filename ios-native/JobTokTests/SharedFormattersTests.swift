import XCTest
@testable import JobTok

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

    func testBigCompanyGating() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func job(stage: String?) throws -> JobPostingRecord {
            let stageJSON = stage.map { "\"\($0)\"" } ?? "null"
            let json = """
            {"id": "j", "title": "t", "is_published": true,
             "created_at": "2026-07-01T12:00:00Z", "company_id": "co-1",
             "company": {"id": "co-1", "name": "Acme", "stage": \(stageJSON)}}
            """.data(using: .utf8)!
            return try decoder.decode(JobPostingRecord.self, from: json)
        }
        XCTAssertTrue(try job(stage: "seed").founderPitchAllowed)
        XCTAssertTrue(try job(stage: nil).founderPitchAllowed)      // unknown = startup
        XCTAssertFalse(try job(stage: "1000+ employees").founderPitchAllowed)
        XCTAssertFalse(try job(stage: "acquisition").founderPitchAllowed)
        XCTAssertFalse(try job(stage: "ipo").founderPitchAllowed)
        XCTAssertTrue(try job(stage: "series_b").founderPitchAllowed)
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
