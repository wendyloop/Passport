import SwiftUI

struct EmployerHomeView: View {
    let fullName: String
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var schoolFilter = ""
    @State private var employerFilter = ""
    @State private var referralOnly = false

    private var filteredCandidates: [Candidate] {
        DemoData.candidates.filter { candidate in
            let schoolMatches = schoolFilter.isEmpty || candidate.school.localizedCaseInsensitiveContains(schoolFilter)
            let employerMatches = employerFilter.isEmpty || candidate.previousEmployers.contains(where: {
                $0.localizedCaseInsensitiveContains(employerFilter)
            })
            let referralMatches = !referralOnly || candidate.referred

            return schoolMatches && employerMatches && referralMatches
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        EmployerHeader(
                            title: "Candidate Feed",
                            subtitle: "Scroll through candidates and review profile context at a glance.",
                            onShowNotifications: onShowNotifications,
                            onSignOut: onSignOut
                        )

                        filterCard

                        ForEach(filteredCandidates) { candidate in
                            CandidateCard(candidate: candidate)
                        }
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Feed", systemImage: "play.square")
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        EmployerHeader(
                            title: "Liked Candidates",
                            subtitle: "Saved candidates remain here for review and follow-up.",
                            onShowNotifications: onShowNotifications,
                            onSignOut: onSignOut
                        )

                        ForEach(DemoData.candidates.prefix(2)) { candidate in
                            SimpleListCard(
                                title: candidate.name,
                                subtitle: "\(candidate.headline)\n\(candidate.school)"
                            )
                        }
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Liked", systemImage: "heart")
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        EmployerHeader(
                            title: "Schedule",
                            subtitle: "Manage availability, approvals, and referral invites.",
                            onShowNotifications: onShowNotifications,
                            onSignOut: onSignOut
                        )

                        SimpleListCard(
                            title: "Open slots",
                            subtitle: "Apr 18, 9:00 AM\nApr 18, 1:30 PM\nApr 19, 11:00 AM"
                        )

                        ForEach(DemoData.employerRequests) { request in
                            SimpleListCard(
                                title: request.title,
                                subtitle: "\(request.status)\n\(request.slots.joined(separator: "\n"))"
                            )
                        }

                        SimpleListCard(
                            title: "Monthly referrals",
                            subtitle: "5 issued per month\nRegistered employers only"
                        )
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }
        }
        .tint(PassportTheme.accent)
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField("School", text: $schoolFilter)
                .textFieldStyle(PassportTextFieldStyle())

            TextField("Previous employer", text: $employerFilter)
                .textFieldStyle(PassportTextFieldStyle())

            Toggle("Referral only", isOn: $referralOnly)
                .toggleStyle(SwitchToggleStyle(tint: PassportTheme.accentSoft))
                .foregroundStyle(PassportTheme.textPrimary)
        }
        .padding(18)
        .background(PassportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
    }
}

private struct EmployerHeader: View {
    let title: String
    let subtitle: String
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    var body: some View {
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
}

private struct CandidateCard: View {
    let candidate: Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PassportTheme.card, PassportTheme.surface, Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 420)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        if candidate.referred {
                            Capsule()
                                .fill(PassportTheme.accentSoft)
                                .frame(width: 88, height: 30)
                                .overlay {
                                    Text("Referral")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.black)
                                }
                        }

                        Capsule()
                            .stroke(PassportTheme.border, lineWidth: 1)
                            .frame(width: 110, height: 30)
                            .overlay {
                                Text(candidate.jobFunction)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PassportTheme.textPrimary)
                            }
                    }
                    .padding()
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate.name)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text(candidate.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text("School: \(candidate.school)")
                            .foregroundStyle(PassportTheme.textSecondary)

                        Text("Previous employers: \(candidate.previousEmployers.joined(separator: ", "))")
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .padding(20)
                }

            Text("Native placeholder for the TikTok-style video card. The SwiftUI version can later be replaced with AVPlayer-backed vertical videos.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
    }
}

struct SimpleListCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text(subtitle)
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
}

#Preview {
    EmployerHomeView(
        fullName: "Jordan",
        onShowNotifications: {},
        onSignOut: {}
    )
}
