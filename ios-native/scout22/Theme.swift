import SwiftUI
import UIKit

enum AppThemePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum PassportTheme {
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let background = dynamic(
        UIColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1),
        UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
    )
    static let surface = dynamic(
        UIColor(red: 1.00, green: 0.99, blue: 0.96, alpha: 1),
        UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    )
    static let card = dynamic(
        UIColor(red: 0.93, green: 0.91, blue: 0.85, alpha: 1),
        UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
    )
    static let border = dynamic(
        UIColor(red: 0.80, green: 0.75, blue: 0.63, alpha: 1),
        UIColor(red: 0.26, green: 0.25, blue: 0.22, alpha: 1)
    )
    static let accent = Color(red: 0.96, green: 0.88, blue: 0.60)
    static let accentSoft = Color(red: 0.34, green: 0.30, blue: 0.17)
    static let textPrimary = dynamic(.black, .white)
    static let textSecondary = dynamic(
        UIColor(red: 0.33, green: 0.30, blue: 0.24, alpha: 1),
        UIColor(red: 0.77, green: 0.75, blue: 0.69, alpha: 1)
    )
    static let textMuted = dynamic(
        UIColor(red: 0.46, green: 0.43, blue: 0.36, alpha: 1),
        UIColor(red: 0.58, green: 0.56, blue: 0.52, alpha: 1)
    )
    static let shadow = dynamic(
        UIColor.black.withAlphaComponent(0.10),
        UIColor.black.withAlphaComponent(0.28)
    )
    static let danger = Color(red: 0.62, green: 0.62, blue: 0.64)
}
