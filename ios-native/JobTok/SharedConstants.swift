import Foundation

/// Identifiers shared between the app and the share extension. This file is
/// compiled into BOTH targets — the app-group UserDefaults contract lives
/// here and nowhere else.
enum SharedConstants {
    static let appGroupID = "group.com.jobtok.shared"

    /// Keys in the app-group UserDefaults suite. Written by the app
    /// (AppSessionStore), read by JobTokShareExtension.
    enum AppGroupKeys {
        static let accessToken = "jobtok.shared.accessToken"
        static let supabaseURL = "jobtok.shared.supabaseURL"
        static let userRole = "jobtok.shared.userRole"
    }

    /// Key in the app's standard UserDefaults holding the encoded session.
    static let sessionDefaultsKey = "jobtok.supabase.session"
}
