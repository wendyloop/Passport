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

    @AppStorage("jobtok.themePreference") private var themePreferenceRaw = AppThemePreference.light.rawValue

    private var themePreference: AppThemePreference {
        get { AppThemePreference(rawValue: themePreferenceRaw) ?? .light }
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

// MARK: - Feed Components

/// Share button for the feed action rail — a ShareLink styled to match
/// FeedActionButton (F10a). Shares the job's landing-page URL.
struct FeedShareButton: View {
    let url: URL

    var body: some View {
        ShareLink(item: url) {
            VStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.38))
                    .clipShape(Circle())
                Text("Share")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FeedActionButton: View {
    let symbol: String
    var isActive: Bool = false
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isActive ? PassportTheme.accent : .white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.38))
                    .clipShape(Circle())
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct FeedEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(PassportTheme.textPrimary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(24)
    }
}

// MARK: - Card Components

struct InfoCard: View {
    let title: String
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)
            Text(details)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .jobTokCard(cornerRadius: 22)
    }
}

struct ProfileStatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
        )
    }
}

// MARK: - Social Links

struct SocialLinkTag: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: "at")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PassportTheme.card.opacity(0.94))
                .foregroundStyle(PassportTheme.textSecondary)
                .clipShape(Capsule())
        }
    }
}

struct SocialLinksRow: View {
    let linkedInURLString: String?
    let instagramUsername: String?
    let tiktokUsername: String?

    private var linkedInURL: URL? { linkedInURLString.flatMap(URL.init(string:)) }
    private var normalizedInstagram: String? { normalizeHandle(instagramUsername) }
    private var normalizedTikTok: String? { normalizeHandle(tiktokUsername) }

    var body: some View {
        if linkedInURL != nil || normalizedInstagram != nil || normalizedTikTok != nil {
            HStack(spacing: 8) {
                if let url = linkedInURL {
                    SocialLinkTag(title: "LinkedIn", url: url)
                }
                if let ig = normalizedInstagram, let url = URL(string: "https://instagram.com/\(ig)") {
                    SocialLinkTag(title: "@\(ig)", url: url)
                }
                if let tt = normalizedTikTok, let url = URL(string: "https://www.tiktok.com/@\(tt)") {
                    SocialLinkTag(title: "@\(tt)", url: url)
                }
            }
        }
    }

    private func normalizeHandle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// Vertical clearances for the feed, derived from the overlaid TikTok-style
// tab bar (content ~52pt + margins) so cards render correctly on every
// device size — the safe-area inset supplies the per-device remainder.
enum FeedLayout {
    /// Bottom padding for a card's CTA overlay: tab bar + breathing room.
    static let cardBottomClearance: CGFloat = 92
    /// Bottom padding for carousel slide text so it stays above the CTA
    /// overlay (progress bar + apply/pitch pills) and the tab bar.
    static let slideContentClearance: CGFloat = 300
}
