import SwiftUI
import UIKit

struct EmployerHomeView: View {
    let fullName: String
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var selectedSchool: String?
    @State private var selectedEmployer: String?
    @State private var selectedJobFunction: String?
    @State private var referralOnly = false
    @State private var activeFilter: FeedFilterKind?
    @State private var selectedTab: EmployerTab = .feed

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
        GeometryReader { proxy in
            let bottomBarInset = FeedPageMetrics.bottomBarInset(for: proxy)
            let contentBottomInset = FeedPageMetrics.contentBottomInset(for: proxy)

            ZStack {
                PassportTheme.background
                    .ignoresSafeArea()

                switch selectedTab {
                case .feed:
                    feedView(proxy: proxy, bottomInset: contentBottomInset)
                case .liked:
                    likedView(bottomInset: contentBottomInset)
                case .schedule:
                    scheduleView(bottomInset: contentBottomInset)
                }
            }
            .overlay(alignment: .top) {
                if selectedTab == .feed {
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
            }
            .overlay(alignment: .bottom) {
                EmployerBottomBar(selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, bottomBarInset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
    }

    private func feedView(proxy: GeometryProxy, bottomInset: CGFloat) -> some View {
        let pageSize = FeedPageMetrics.pageSize(for: proxy)

        return ZStack {
            if filteredCandidates.isEmpty {
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
                .contentMargins(.zero, for: .scrollContent)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(PassportTheme.background)
    }

    private func likedView(bottomInset: CGFloat) -> some View {
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PassportTheme.background)
    }

    private func scheduleView(bottomInset: CGFloat) -> some View {
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PassportTheme.background)
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
            .background(referralOnly ? PassportTheme.accent.opacity(0.35) : PassportTheme.surface.opacity(0.86))
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

    var body: some View {
        ZStack {
            TikTokVideoSurface(candidate: candidate, pulse: pulse)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.00),
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.88)
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

            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse.toggle()
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

private enum EmployerTab: String, CaseIterable {
    case feed
    case liked
    case schedule
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
        proxy.size
    }

    static func bottomOverlayPadding(for proxy: GeometryProxy) -> CGFloat {
        let height = pageSize(for: proxy).height

        if height <= 700 {
            return 62
        } else if height <= 820 {
            return 72
        } else {
            return 82
        }
    }

    static var bottomBarHeight: CGFloat { 56 }

    static func bottomBarInset(for proxy: GeometryProxy) -> CGFloat {
        max(8, proxy.safeAreaInsets.bottom + 6)
    }

    static func contentBottomInset(for proxy: GeometryProxy) -> CGFloat {
        bottomOverlayPadding(for: proxy) + bottomBarHeight + bottomBarInset(for: proxy)
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

private struct EmployerBottomBar: View {
    @Binding var selectedTab: EmployerTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PassportTheme.border.opacity(0.22))
                .frame(height: 0.8)

            HStack(spacing: 0) {
                ForEach(EmployerTab.allCases, id: \.rawValue) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon(for: tab))
                                .font(.system(size: 17, weight: .semibold))
                            Text(label(for: tab))
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .foregroundStyle(selectedTab == tab ? PassportTheme.textPrimary : PassportTheme.textSecondary)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(selectedTab == tab ? PassportTheme.accent : Color.clear)
                                .frame(width: 34, height: 3)
                                .offset(y: -7)
                        }
                    }
                }
            }
            .frame(height: FeedPageMetrics.bottomBarHeight)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.94))
    }

    private func label(for tab: EmployerTab) -> String {
        switch tab {
        case .feed:
            "Feed"
        case .liked:
            "Liked"
        case .schedule:
            "Schedule"
        }
    }

    private func icon(for tab: EmployerTab) -> String {
        switch tab {
        case .feed:
            "play.square.fill"
        case .liked:
            "heart.fill"
        case .schedule:
            "calendar"
        }
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
