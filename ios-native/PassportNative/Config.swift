import Foundation

struct PassportConfig {
    let supabaseURL: String
    let supabaseAnonKey: String
    let redirectScheme: String

    var isPlaceholderURL: Bool {
        supabaseURL.contains("YOUR_PROJECT_REF") || supabaseURL.contains("Set SUPABASE_URL")
    }

    var isPlaceholderKey: Bool {
        supabaseAnonKey.contains("YOUR_SUPABASE_ANON_KEY") || supabaseAnonKey.contains("Set SUPABASE_ANON_KEY")
    }

    var debugSummary: String {
        let shortenedURL = supabaseURL.isEmpty ? "<empty>" : supabaseURL
        let keyLength = supabaseAnonKey.count
        return "url=\(shortenedURL) keyLength=\(keyLength) redirect=\(redirectScheme)"
    }

    static func load() -> PassportConfig {
        let rawProjectRef = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_REF") as? String
        guard
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let rawKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let rawRedirectScheme = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_REDIRECT_SCHEME") as? String
        else {
            let projectRef = sanitize(rawProjectRef ?? "")
            if !projectRef.isEmpty {
                return PassportConfig(
                    supabaseURL: "https://\(projectRef).supabase.co",
                    supabaseAnonKey: sanitize(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""),
                    redirectScheme: sanitize(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_REDIRECT_SCHEME") as? String ?? "passportnative")
                )
            }
            return PassportConfig(
                supabaseURL: "Set SUPABASE_URL in the target build settings",
                supabaseAnonKey: "Set SUPABASE_ANON_KEY in the target build settings",
                redirectScheme: "passportnative"
            )
        }

        let projectRef = sanitize(rawProjectRef ?? "")
        let sanitizedURL = sanitize(rawURL)
        let url: String
        if (sanitizedURL.isEmpty || sanitizedURL == "https:") && !projectRef.isEmpty {
            url = "https://\(projectRef).supabase.co"
        } else {
            url = sanitizedURL
        }
        let key = sanitize(rawKey)
        let redirectScheme = sanitize(rawRedirectScheme)

        return PassportConfig(
            supabaseURL: url,
            supabaseAnonKey: key,
            redirectScheme: redirectScheme
        )
    }

    private static func sanitize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
