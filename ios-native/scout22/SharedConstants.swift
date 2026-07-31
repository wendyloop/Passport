import Foundation

/// Identifiers shared between the app and the share extension. This file is
/// compiled into BOTH targets — the app-group UserDefaults contract lives
/// here and nowhere else.
enum SharedConstants {
    static let appGroupID = "group.com.jobtok.shared"

    /// Keys in the app-group UserDefaults suite. Written by the app
    /// (AppSessionStore), read by Scout22ShareExtension.
    enum AppGroupKeys {
        static let accessToken = "jobtok.shared.accessToken"
        static let supabaseURL = "jobtok.shared.supabaseURL"
        static let userRole = "jobtok.shared.userRole"
    }

    /// Key in the app's standard UserDefaults holding the encoded session.
    static let sessionDefaultsKey = "jobtok.supabase.session"
}

/// F10 share-a-job loop. FILL-IN LATER (tracked in docs/DEFERRED_WORK.md):
/// once tryscout22.com hosts the landing page + AASA file, point
/// shareBaseURL there and add Associated Domains for universal links.
/// Until then links go to the Supabase-hosted landing function, which
/// renders the OG preview and the get-the-app CTA.
enum ShareConfig {
    static let shareBaseURL = "https://zqfurscyhmxlvrfendnc.supabase.co/functions/v1/job-share"

    static func shareURL(forJobID id: String) -> URL? {
        URL(string: "\(shareBaseURL)/\(id)")
    }
}
