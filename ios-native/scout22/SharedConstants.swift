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
    /// Universal-link host. Paired with applinks:tryscout22.com in the
    /// entitlement and the AASA file on the site: iOS opens these in the app
    /// when it's installed, and falls back to the web page when it isn't.
    ///
    /// Replaced the Supabase functions URL, which Supabase serves as
    /// text/plain + nosniff (they block HTML on their shared domain), so
    /// every shared link rendered as raw source instead of a page.
    static let shareBaseURL = "https://tryscout22.com/j"

    static func shareURL(forJobID id: String) -> URL? {
        URL(string: "\(shareBaseURL)/\(id)")
    }

    /// Job id from either share link shape, or nil if this isn't one.
    ///
    /// Two shapes exist on purpose: `jobtok://job/{id}` is the legacy custom
    /// scheme, still handled so links shared before universal links shipped
    /// keep working; `https://tryscout22.com/j/{id}` is the universal link,
    /// which is the only shape that opens the app from Instagram, Safari or
    /// a link preview.
    static func jobID(fromDeepLink url: URL) -> String? {
        let candidate: String?
        if url.scheme == "https", url.host == "tryscout22.com" {
            // /j/{id} — reject anything else on the domain.
            let parts = url.pathComponents.filter { $0 != "/" }
            candidate = (parts.count == 2 && parts[0] == "j") ? parts[1] : nil
        } else if url.host == "job" {
            candidate = url.lastPathComponent
        } else {
            return nil
        }
        guard let id = candidate, !id.isEmpty, id != "job", id != "j" else { return nil }
        return id
    }
}
