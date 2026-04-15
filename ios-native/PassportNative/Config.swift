import Foundation

struct PassportConfig {
    let supabaseURL: String
    let supabaseAnonKey: String

    static func load() -> PassportConfig {
        guard
            let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            return PassportConfig(
                supabaseURL: "Set SUPABASE_URL in the target build settings",
                supabaseAnonKey: "Set SUPABASE_ANON_KEY in the target build settings"
            )
        }

        return PassportConfig(supabaseURL: url, supabaseAnonKey: key)
    }
}
