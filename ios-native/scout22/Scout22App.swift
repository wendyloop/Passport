import SwiftUI

@main
struct Scout22App: App {
    @AppStorage("jobtok.themePreference") private var themePreferenceRaw = AppThemePreference.light.rawValue

    init() {
        // Card carousel templates draw with bundled display fonts.
        CarouselFonts.registerAll()
    }

    private var themePreference: AppThemePreference {
        AppThemePreference(rawValue: themePreferenceRaw) ?? .light
    }

    var body: some Scene {
        WindowGroup {
            NativeRootView()
                .preferredColorScheme(themePreference.colorScheme)
        }
    }
}
