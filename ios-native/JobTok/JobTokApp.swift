import SwiftUI

@main
struct JobTokApp: App {
    @AppStorage("jobtok.themePreference") private var themePreferenceRaw = AppThemePreference.dark.rawValue

    init() {
        // Card carousel templates draw with bundled display fonts.
        CarouselFonts.registerAll()
    }

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
