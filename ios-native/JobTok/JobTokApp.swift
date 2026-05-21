import SwiftUI

@main
struct JobTokApp: App {
    @AppStorage("jobtok.themePreference") private var themePreferenceRaw = AppThemePreference.dark.rawValue

    private var themePreference: AppThemePreference {
        AppThemePreference(rawValue: themePreferenceRaw) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            NativeRootView()
                .preferredColorScheme(themePreference.colorScheme)
        }
    }
}
