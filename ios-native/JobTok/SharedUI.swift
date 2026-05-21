import SwiftUI

struct HeaderAction: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PassportTheme.textPrimary)
                .frame(width: 38, height: 38)
                .background(PassportTheme.card.opacity(0.98))
                .clipShape(Circle())
                .overlay(Circle().stroke(PassportTheme.border.opacity(0.75), lineWidth: 1))
                .shadow(color: PassportTheme.shadow, radius: 10, y: 5)
        }
    }
}

struct ProfileSettingsDrawer: View {
    let onClose: () -> Void
    let onLogOut: () -> Void
    let onDeleteAccount: () -> Void

    @AppStorage("jobtok.themePreference") private var themePreferenceRaw = AppThemePreference.dark.rawValue

    private var themePreference: AppThemePreference {
        get { AppThemePreference(rawValue: themePreferenceRaw) ?? .dark }
        nonmutating set { themePreferenceRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(PassportTheme.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                HStack(spacing: 8) {
                    ForEach(AppThemePreference.allCases) { option in
                        Button {
                            themePreference = option
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(themePreference == option ? PassportTheme.accent : PassportTheme.card)
                                .foregroundStyle(themePreference == option ? Color.black : PassportTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .jobTokCard(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 12) {
                Text("Account")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                Button(action: onLogOut) {
                    settingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Log Out")
                }
                .buttonStyle(.plain)

                Button(action: onDeleteAccount) {
                    settingsRow(symbol: "trash", title: "Delete Account", isDestructive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .jobTokCard(cornerRadius: 22)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PassportTheme.background)
    }

    private func settingsRow(symbol: String, title: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 20)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(PassportTheme.card)
        .foregroundStyle(isDestructive ? Color.red.opacity(0.92) : PassportTheme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
        )
    }
}

extension View {
    func jobTokCard(cornerRadius: CGFloat = 24, fill: Color = PassportTheme.surface) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PassportTheme.border.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: PassportTheme.shadow, radius: 16, y: 10)
    }

    func jobTokChromeCapsule() -> some View {
        background(PassportTheme.surface.opacity(0.96))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(PassportTheme.border.opacity(0.6), lineWidth: 1))
            .shadow(color: PassportTheme.shadow, radius: 14, y: 8)
    }
}
