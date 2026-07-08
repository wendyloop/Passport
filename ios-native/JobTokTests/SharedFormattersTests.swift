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
