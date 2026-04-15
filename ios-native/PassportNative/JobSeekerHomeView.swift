import SwiftUI

struct JobSeekerHomeView: View {
    let fullName: String
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(
                            title: "Profile",
                            subtitle: "Your public candidate profile for employers."
                        )

                        profileCard

                        SimpleProfileCard(
                            title: "Resume import",
                            details: "This native app is ready for a future Supabase-backed resume parsing flow."
                        )

                        SimpleProfileCard(
                            title: "Intro video",
                            details: "Video upload and playback can be added natively with PhotosPicker and AVKit."
                        )
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(
                            title: "Interview Requests",
                            subtitle: "Requests appear here after employers like your profile."
                        )

                        ForEach(DemoData.jobSeekerRequests) { request in
                            SimpleProfileCard(
                                title: "\(request.title) • \(request.status)",
                                details: request.slots.joined(separator: "\n")
                            )
                        }
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Requests", systemImage: "calendar")
            }
        }
        .tint(PassportTheme.accent)
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)

                    Text(subtitle)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                Spacer()

                Button(action: onShowNotifications) {
                    Image(systemName: "bell")
                        .foregroundStyle(PassportTheme.textPrimary)
                        .padding(10)
                        .background(PassportTheme.surface)
                        .clipShape(Circle())
                }
            }

            Button("Sign out", action: onSignOut)
                .foregroundStyle(PassportTheme.danger)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fullName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)

            Text("Senior designer focused on marketplace trust and candidate experience.")
                .foregroundStyle(PassportTheme.textPrimary)

            Divider().overlay(PassportTheme.border)

            Text("School: Stanford University")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Employers: Figma, Notion")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Referral badge: Yes")
                .foregroundStyle(PassportTheme.textSecondary)
            Text("Job function: Design")
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
    }
}

private struct SimpleProfileCard: View {
    let title: String
    let details: String

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text(details)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
    }

    var body: some View {
        contentView
    }
}

#Preview {
    JobSeekerHomeView(
        fullName: "Maya Chen",
        onShowNotifications: {},
        onSignOut: {}
    )
}
