import Foundation

/// Maps raw backend errors (Postgres constraint names, trigger messages)
/// to copy a person can act on. Brittle by nature — these string matches
/// track constraint names in supabase/migrations — so it lives in one
/// unit-testable place instead of inside the session store.
enum SupabaseErrorMapping {
    static func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription

        if message.localizedCaseInsensitiveContains("jobs_source_url_unique")
            || (message.localizedCaseInsensitiveContains("duplicate key value violates unique constraint")
                && message.localizedCaseInsensitiveContains("source_url")) {
            return "This post has already been imported."
        }

        if message.localizedCaseInsensitiveContains("profiles_handle_unique_idx")
            || message.localizedCaseInsensitiveContains("duplicate key value violates unique constraint")
                && message.localizedCaseInsensitiveContains("handle") {
            return "That handle is already taken. Try a different one."
        }

        if message.localizedCaseInsensitiveContains("handle can only be changed once every 30 days") {
            return "You can only change your handle once every 30 days."
        }

        if message.localizedCaseInsensitiveContains("full name can only be changed once every 7 days") {
            return "You can only change your full name once every 7 days."
        }

        if message.localizedCaseInsensitiveContains("profiles_handle_format") {
            return "Handles can only use lowercase letters, numbers, and underscores."
        }

        if message.localizedCaseInsensitiveContains("job_applications_job_id_candidate_profile_id_key")
            || message.localizedCaseInsensitiveContains("duplicate key value violates unique constraint")
                && message.localizedCaseInsensitiveContains("job_applications") {
            return "You already applied to this job."
        }

        return message
    }
}
