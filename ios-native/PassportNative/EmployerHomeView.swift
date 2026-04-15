import SwiftUI

struct EmployerHomeView: View {
    let fullName: String
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var selectedSchool: String?
    @State private var selectedEmployer: String?
    @State private var selectedJobFunction: String?
    @State private var referralOnly = false
    @State private var activeFilter: FeedFilterKind?

    private var filteredCandidates: [Candidate] {
        DemoData.candidates.filter { candidate in
            let schoolMatches = selectedSchool == nil || candidate.school == selectedSchool
            let employerMatches = selectedEmployer == nil || candidate.previousEmployers.contains(selectedEmployer!)
            let functionMatches = selectedJobFunction == nil || candidate.jobFunction == selectedJobFunction
            let referralMatches = !referralOnly || candidate.referred

            return schoolMatches && employerMatches && functionMatches && referralMatches
        }
    }

    private var schoolOptions: [String] {
        Array(Set(DemoData.candidates.map(\.school))).sorted()
    }

    private var employerOptions: [String] {
        Array(Set(DemoData.candidates.flatMap(\.previousEmployers))).sorted()
    }

    private var jobFunctionOptions: [String] {
        Array(Set(DemoData.candidates.map(\.jobFunction))).sorted()
    }

    var body: some View {
        TabView {
            feedView
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

    private var feedView: some View {
        GeometryReader { proxy in
            let pageSize = FeedPageMetrics.pageSize(for: proxy)
            let bottomInset = FeedPageMetrics.bottomOverlayPadding(for: proxy)

            ZStack {
                if filteredCandidates.isEmpty {
                    PassportTheme.background
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Text("No candidates match your filters")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(PassportTheme.textPrimary)

                        Button("Reset filters") {
                            selectedSchool = nil
                            selectedEmployer = nil
                            selectedJobFunction = nil
                            referralOnly = false
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredCandidates) { candidate in
                                FullScreenCandidateCard(
                                    candidate: candidate,
                                    containerSize: pageSize,
                                    bottomInset: bottomInset
                                )
                                .frame(width: pageSize.width, height: pageSize.height)
                                .id(candidate.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .ignoresSafeArea()
                }
            }
            .background(PassportTheme.background)
        }
        .overlay(alignment: .top) {
            EmployerFeedTopBar(
                selectedSchool: $selectedSchool,
                selectedEmployer: $selectedEmployer,
                selectedJobFunction: $selectedJobFunction,
                referralOnly: $referralOnly,
                activeFilter: $activeFilter,
                onShowNotifications: onShowNotifications,
                onSignOut: onSignOut
            )
            .padding(.horizontal, 10)
            .padding(.top, FeedPageMetrics.topOverlayPadding)
        }
        .sheet(item: $activeFilter) { filter in
            NavigationStack {
                FilterSelectionSheet(
                    title: filter.title,
                    options: options(for: filter),
                    selection: selectionBinding(for: filter)
                )
            }
            .presentationDetents([.medium, .large])
        }
        .ignoresSafeArea()
    }

    private func options(for filter: FeedFilterKind) -> [String] {
        switch filter {
        case .school:
            schoolOptions
        case .employer:
            employerOptions
        case .jobFunction:
            jobFunctionOptions
        case .referral:
            []
        }
    }

    private func selectionBinding(for filter: FeedFilterKind) -> Binding<String?> {
        switch filter {
        case .school:
            $selectedSchool
        case .employer:
            $selectedEmployer
        case .jobFunction:
            $selectedJobFunction
        case .referral:
            .constant(nil)
        }
    }

}

private struct EmployerFeedTopBar: View {
    @Binding var selectedSchool: String?
    @Binding var selectedEmployer: String?
    @Binding var selectedJobFunction: String?
    @Binding var referralOnly: Bool
    @Binding var activeFilter: FeedFilterKind?
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: selectedSchool ?? "School",
                        action: { activeFilter = .school }
                    )
                    FilterChip(
                        title: selectedEmployer ?? "Employers",
                        action: { activeFilter = .employer }
                    )
                    FilterChip(
                        title: selectedJobFunction ?? "Job Function",
                        action: { activeFilter = .jobFunction }
                    )
                    ReferralChip(referralOnly: $referralOnly)
                }
            }

            Spacer(minLength: 8)

            ActionCircle(symbol: "bell.fill", action: onShowNotifications)
            ActionCircle(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.38))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PassportTheme.border.opacity(0.32), lineWidth: 1)
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

                ActionCircle(symbol: "bell.fill", action: onShowNotifications)
            }

            Button("Sign out", action: onSignOut)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PassportTheme.danger)
        }
    }
}

private struct ActionCircle: View {
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

private struct FilterChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(PassportTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PassportTheme.surface.opacity(0.86))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(PassportTheme.border.opacity(0.75), lineWidth: 1))
        }
    }
}

private struct ReferralChip: View {
    @Binding var referralOnly: Bool

    var body: some View {
        Button {
            referralOnly.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(referralOnly ? "Referrals Only" : "Referrals")
                if referralOnly {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(PassportTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background((referralOnly ? PassportTheme.accent.opacity(0.35) : PassportTheme.surface.opacity(0.86)))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(PassportTheme.border.opacity(0.75), lineWidth: 1))
        }
    }
}

private struct FullScreenCandidateCard: View {
    let candidate: Candidate
    let containerSize: CGSize
    let bottomInset: CGFloat

    @State private var pulse = false
    @State private var barFill: CGFloat = 0.15

    var body: some View {
        ZStack {
            TikTokVideoSurface(candidate: candidate, pulse: pulse)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.00),
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            if candidate.referred {
                                Label("Referral", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(PassportTheme.accentSoft)
                                    .foregroundStyle(.black)
                                    .clipShape(Capsule())
                            }

                            Text(candidate.jobFunction.uppercased())
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(PassportTheme.surface.opacity(0.92))
                                .foregroundStyle(PassportTheme.textPrimary)
                                .clipShape(Capsule())
                        }

                        Text(candidate.name)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text(candidate.headline)
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("School • \(candidate.school)")
                            Text("Employers • \(candidate.previousEmployers.joined(separator: ", "))")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PassportTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(0..<12, id: \.self) { index in
                                    Capsule()
                                        .fill(index < Int(barFill * 12) ? PassportTheme.accent : PassportTheme.textPrimary.opacity(0.18))
                                        .frame(height: 4)
                                }
                            }

                            Text("Auto-play placeholder for the candidate intro. Replace this with AVPlayer when you wire real videos.")
                                .font(.footnote)
                                .foregroundStyle(PassportTheme.textSecondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 18) {
                        SideAction(symbol: "heart.fill", label: "Like")
                        SideAction(symbol: "bookmark.fill", label: "Save")
                        SideAction(symbol: "paperplane.fill", label: "Request")
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, bottomInset)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
        .onAppear {
            pulse = false
            barFill = 0.15

            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }

            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                barFill = 1.0
            }
        }
    }
}

private enum FeedFilterKind: String, Identifiable {
    case school
    case employer
    case jobFunction
    case referral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .school:
            "School"
        case .employer:
            "Employers"
        case .jobFunction:
            "Job Function"
        case .referral:
            "Referrals"
        }
    }
}

private enum FeedPageMetrics {
    static var topOverlayPadding: CGFloat {
        let topInset =
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .safeAreaInsets.top ?? 0

        return max(4, topInset * 0.25)
    }

    static func pageSize(for proxy: GeometryProxy) -> CGSize {
        let screenBounds = UIScreen.main.bounds.size
        let width = max(proxy.size.width, screenBounds.width)
        let height = max(
            proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
            screenBounds.height
        )

        return CGSize(width: width, height: height)
    }

    static func bottomOverlayPadding(for proxy: GeometryProxy) -> CGFloat {
        let height = pageSize(for: proxy).height

        if height <= 700 {
            return 84
        } else if height <= 820 {
            return 96
        } else {
            return 112
        }
    }
}

private struct FilterSelectionSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button("All") {
                selection = nil
                dismiss()
            }
            .foregroundStyle(PassportTheme.textPrimary)
            .listRowBackground(PassportTheme.surface)

            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(PassportTheme.accent)
                        }
                    }
                    .foregroundStyle(PassportTheme.textPrimary)
                }
                .listRowBackground(PassportTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PassportTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TikTokVideoSurface: View {
    let candidate: Candidate
    let pulse: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PassportTheme.background,
                    PassportTheme.card,
                    Color(red: 0.04, green: 0.14, blue: 0.32),
                    Color.black
                ],
                startPoint: pulse ? .topLeading : .bottomTrailing,
                endPoint: pulse ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()

            Circle()
                .fill(PassportTheme.accent.opacity(0.30))
                .frame(width: 420, height: 420)
                .blur(radius: 64)
                .offset(x: pulse ? 120 : -110, y: -280)

            Circle()
                .fill(PassportTheme.accentSoft.opacity(0.24))
                .frame(width: 360, height: 360)
                .blur(radius: 54)
                .offset(x: pulse ? -130 : 110, y: 140)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            PassportTheme.accent.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 96, height: 96)

                    Image(systemName: "play.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary.opacity(0.92))
                }

                Text(candidate.name.split(separator: " ").first.map(String.init) ?? candidate.name)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary.opacity(0.12))
            }
        }
    }
}

private struct SideAction: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(PassportTheme.surface.opacity(0.94))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                }
                .overlay(Circle().stroke(PassportTheme.border, lineWidth: 1))

            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
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
