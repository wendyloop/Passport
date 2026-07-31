import XCTest
@testable import scout22

// These lock in the constraint-name string matching. If a migration renames
// a constraint, the corresponding case here should fail and force the copy
// to be revisited.
final class SupabaseErrorMappingTests: XCTestCase {
    private struct FakeError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    func testDuplicateSourceURL() {
        let message = SupabaseErrorMapping.friendlyMessage(
            for: FakeError(#"duplicate key value violates unique constraint "jobs_source_url_unique""#)
        )
        XCTAssertEqual(message, "This post has already been imported.")
    }

    func testDuplicateHandle() {
        let message = SupabaseErrorMapping.friendlyMessage(
            for: FakeError(#"duplicate key value violates unique constraint "profiles_handle_unique_idx""#)
        )
        XCTAssertEqual(message, "That handle is already taken. Try a different one.")
    }

    func testHandleChangeCooldown() {
        let message = SupabaseErrorMapping.friendlyMessage(
            for: FakeError("Handle can only be changed once every 30 days")
        )
        XCTAssertEqual(message, "You can only change your handle once every 30 days.")
    }

    func testHandleFormatConstraint() {
        let message = SupabaseErrorMapping.friendlyMessage(
            for: FakeError(#"new row violates check constraint "profiles_handle_format""#)
        )
        XCTAssertEqual(message, "Handles can only use lowercase letters, numbers, and underscores.")
    }

    func testDuplicateApplication() {
        let message = SupabaseErrorMapping.friendlyMessage(
            for: FakeError(#"duplicate key value violates unique constraint "job_applications_job_id_candidate_profile_id_key""#)
        )
        XCTAssertEqual(message, "You already applied to this job.")
    }

    func testUnrecognizedErrorPassesThrough() {
        let message = SupabaseErrorMapping.friendlyMessage(for: FakeError("something novel went wrong"))
        XCTAssertEqual(message, "something novel went wrong")
    }
}
