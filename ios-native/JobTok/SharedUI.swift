import SwiftUI

struct HeaderAction: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PassportTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(PassportTheme.surface.opacity(0.95))
                .clipShape(Circle())
                .overlay(Circle().stroke(PassportTheme.border, lineWidth: 1))
        }
    }
}
