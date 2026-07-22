import SwiftUI
import CoreText

// Bundled display fonts for the card carousel templates (Fonts/ folder,
// Latin subsets, all OFL-licensed — ~500KB total). Registered at runtime
// via CoreText so no Info.plist UIAppFonts entry is needed; call
// CarouselFonts.registerAll() once at app start (JobTokApp does).
//
// Every accessor falls back gracefully: if a face failed to register,
// Font.custom silently renders the system font, so a missing file can
// never crash the feed — FontRegistrationTests asserts they all load.

enum CarouselFonts {
    /// PostScript names of every bundled face; the single source of truth
    /// the registration test asserts against.
    static let postScriptNames: [String] = [
        "Archivo-Black", "Archivo-BlackItalic", "Archivo-Bold",
        "Archivo-BoldItalic", "Archivo-ExtraBoldItalic",
        "PlayfairDisplay-Regular", "PlayfairDisplay-Italic",
        "PlayfairDisplay-Bold", "PlayfairDisplay-BoldItalic",
        "DMMono-Regular", "DMMono-Medium",
        "Baloo2-SemiBold", "Baloo2-Bold", "Baloo2-ExtraBold",
        "Chewy-Regular", "VT323-Regular", "Italianno-Regular",
        "GochiHand-Regular",
    ]

    private static var registered = false

    /// Idempotent; safe to call from tests and the app entry point alike.
    static func registerAll() {
        guard !registered else { return }
        registered = true
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else {
            AppLog.ui.error("CarouselFonts: no bundled fonts found")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, _ in true }
    }

    // MARK: - Typed accessors

    static func archivoBlack(_ size: CGFloat) -> Font { .custom("Archivo-Black", size: size) }
    static func archivoBlackItalic(_ size: CGFloat) -> Font { .custom("Archivo-BlackItalic", size: size) }
    static func archivoBold(_ size: CGFloat) -> Font { .custom("Archivo-Bold", size: size) }
    static func archivoBoldItalic(_ size: CGFloat) -> Font { .custom("Archivo-BoldItalic", size: size) }
    static func archivoExtraBoldItalic(_ size: CGFloat) -> Font { .custom("Archivo-ExtraBoldItalic", size: size) }

    static func playfair(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Regular", size: size) }
    static func playfairItalic(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Italic", size: size) }
    static func playfairBold(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Bold", size: size) }
    static func playfairBoldItalic(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-BoldItalic", size: size) }

    static func dmMono(_ size: CGFloat) -> Font { .custom("DMMono-Regular", size: size) }
    static func dmMonoMedium(_ size: CGFloat) -> Font { .custom("DMMono-Medium", size: size) }

    static func balooSemiBold(_ size: CGFloat) -> Font { .custom("Baloo2-SemiBold", size: size) }
    static func balooBold(_ size: CGFloat) -> Font { .custom("Baloo2-Bold", size: size) }
    static func balooExtraBold(_ size: CGFloat) -> Font { .custom("Baloo2-ExtraBold", size: size) }

    static func chewy(_ size: CGFloat) -> Font { .custom("Chewy-Regular", size: size) }
    static func vt323(_ size: CGFloat) -> Font { .custom("VT323-Regular", size: size) }
    static func italianno(_ size: CGFloat) -> Font { .custom("Italianno-Regular", size: size) }
    static func gochiHand(_ size: CGFloat) -> Font { .custom("GochiHand-Regular", size: size) }
}
