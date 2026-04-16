import SwiftUI
import AVFoundation
import UIKit

struct EmployerHomeView: View {
    let fullName: String
    let candidates: [Candidate]
    let likedCandidates: [Candidate]
    let availabilitySlots: [AvailabilitySlotRecord]
    let approvals: [EmployerApprovalItem]
    let onRefresh: () -> Void
    let onLikeCandidate: (String) -> Void
    let onAddAvailabilitySlot: (Date, Date) -> Void
    let onRespondToApproval: (String, Bool) -> Void
    let onIssueReferral: (String?) -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void

    @State private var selectedTab: EmployerTab = .feed
    @State private var selectedSchool: String?
    @State private var selectedEmployer: String?
    @State private var selectedJobFunction: String?
    @State private var referralOnly = false
    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(1800)
    @State private var referralEmail = ""

    private var filteredCandidates: [Candidate] {
        candidates.filter { candidate in
            let schoolMatches = selectedSchool == nil || candidate.school == selectedSchool
            let employerMatches = selectedEmployer == nil || candidate.previousEmployers.contains(selectedEmployer!)
            let functionMatches = selectedJobFunction == nil || candidate.jobFunction == selectedJobFunction
            let referralMatches = !referralOnly || candidate.referred
            return schoolMatches && employerMatches && functionMatches && referralMatches
        }
    }

    private var schoolOptions: [String] {
        Array(Set(candidates.map(\.school))).sorted()
    }

    private var employerOptions: [String] {
        Array(Set(candidates.flatMap(\.previousEmployers))).sorted()
    }

    private var jobFunctionOptions: [String] {
        Array(Set(candidates.map(\.jobFunction))).sorted()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                PassportTheme.background
                    .ignoresSafeArea()

                switch selectedTab {
                case .feed:
                    feedView(proxy: proxy)
                case .liked:
                    likedView
                case .schedule:
                    scheduleView
                }

                bottomBar
            }
        }
    }

    private func feedView(proxy: GeometryProxy) -> some View {
        let pageSize = proxy.size

        return ZStack(alignment: .top) {
            if filteredCandidates.isEmpty {
                VStack(spacing: 16) {
                    Text("No candidates match these filters.")
                        .font(.headline)
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
                            EmployerFeedCard(candidate: candidate) {
                                onLikeCandidate(candidate.id)
                            }
                            .frame(width: pageSize.width, height: pageSize.height)
                            .id(candidate.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
            }

            feedTopBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
        }
        .ignoresSafeArea()
    }

    private var likedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(
                    title: "Liked Candidates",
                    subtitle: "Candidates you liked stay here so you can revisit them."
                )

                if likedCandidates.isEmpty {
                    emptyCard(text: "No liked candidates yet.")
                } else {
                    ForEach(likedCandidates) { candidate in
                        SimpleListCard(
                            title: candidate.name,
                            subtitle: "\(candidate.headline)\n\(candidate.school)\n\(candidate.previousEmployers.joined(separator: ", "))"
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
        .background(PassportTheme.background)
    }

    private var scheduleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(
                    title: "Schedule",
                    subtitle: "Manual availability is active now. Google Calendar linkage is a later TODO."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Add availability")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)

                    DatePicker("Start", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                        .tint(PassportTheme.accent)
                    DatePicker("End", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                        .tint(PassportTheme.accent)

                    Button("Add time slot") {
                        onAddAvailabilitySlot(startAt, endAt)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(18)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Referral invites")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)

                    TextField("Candidate email (optional)", text: $referralEmail)
                        .textFieldStyle(PassportTextFieldStyle())

                    Button("Issue referral invite") {
                        let trimmed = referralEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        onIssueReferral(trimmed.isEmpty ? nil : trimmed)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PassportTheme.card)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(18)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Open slots")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)

                    if availabilitySlots.isEmpty {
                        emptyCard(text: "No availability published yet.")
                    } else {
                        ForEach(availabilitySlots) { slot in
                            SimpleListCard(
                                title: slotTimeTitle(slot),
                                subtitle: "\(slotTimeBody(slot))\nStatus: \(slot.slotStatus)"
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pending approvals")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)

                    if approvals.isEmpty {
                        emptyCard(text: "No interview approvals waiting right now.")
                    } else {
                        ForEach(approvals) { approval in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(approval.candidateName)
                                    .font(.headline)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                Text(approval.slotLabel)
                                    .foregroundStyle(PassportTheme.textSecondary)

                                HStack(spacing: 10) {
                                    Button("Approve") {
                                        onRespondToApproval(approval.id, true)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(PassportTheme.accent)
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    Button("Decline") {
                                        onRespondToApproval(approval.id, false)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(PassportTheme.danger)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                            .padding(18)
                            .background(PassportTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 140)
        }
        .background(PassportTheme.background)
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
                ActionCircle(symbol: "arrow.clockwise", action: onRefresh)
                ActionCircle(symbol: "bell.fill", action: onShowNotifications)
            }

            HStack(spacing: 10) {
                Text("Signed in as \(fullName)")
                    .font(.subheadline)
                    .foregroundStyle(PassportTheme.textSecondary)
                Spacer()
                Button("Sign out", action: onSignOut)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PassportTheme.danger)
            }
        }
    }

    private var feedTopBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FeedMenuChip(title: selectedSchool ?? "School", options: schoolOptions) {
                            selectedSchool = $0
                        }
                        FeedMenuChip(title: selectedEmployer ?? "Employers", options: employerOptions) {
                            selectedEmployer = $0
                        }
                        FeedMenuChip(title: selectedJobFunction ?? "Job Function", options: jobFunctionOptions) {
                            selectedJobFunction = $0
                        }
                        Button {
                            referralOnly.toggle()
                        } label: {
                            Text(referralOnly ? "Referrals Only" : "Referrals")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PassportTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(referralOnly ? PassportTheme.accent.opacity(0.35) : PassportTheme.surface.opacity(0.86))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 8)

                ActionCircle(symbol: "bell.fill", action: onShowNotifications)
                ActionCircle(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.38))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(PassportTheme.border.opacity(0.28), lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(EmployerTab.allCases, id: \.rawValue) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.label)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? PassportTheme.textPrimary : PassportTheme.textSecondary)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.94))
        .overlay(Rectangle().fill(PassportTheme.border.opacity(0.22)).frame(height: 0.8), alignment: .top)
    }

    private func emptyCard(text: String) -> some View {
        Text(text)
            .foregroundStyle(PassportTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(PassportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func slotTimeTitle(_ slot: AvailabilitySlotRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: slot.startAt)
    }

    private func slotTimeBody(_ slot: AvailabilitySlotRecord) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: slot.endAt)) • \(slot.source)"
    }
}

private enum EmployerTab: String, CaseIterable {
    case feed
    case liked
    case schedule

    var label: String {
        switch self {
        case .feed: return "Feed"
        case .liked: return "Liked"
        case .schedule: return "Schedule"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "play.square.fill"
        case .liked: return "heart.fill"
        case .schedule: return "calendar"
        }
    }
}

private struct EmployerFeedCard: View {
    let candidate: Candidate
    let onLike: () -> Void

    var body: some View {
        ZStack {
            TikTokVideoSurface(candidate: candidate)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.92)
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
                .padding(.bottom, 96)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onLike)
    }
}

private struct FeedMenuChip: View {
    let title: String
    let options: [String]
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            Button("All") { onSelect(nil) }
            ForEach(options, id: \.self) { option in
                Button(option) { onSelect(option) }
            }
        } label: {
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

private struct TikTokVideoSurface: View {
    let candidate: Candidate

    var body: some View {
        ZStack {
            if let url = DemoVideoCatalog.url(for: candidate.demoVideoName, localPath: candidate.localVideoPath, remoteURL: candidate.remoteVideoURL) {
                LoopingVideoSurface(url: url)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        PassportTheme.background,
                        PassportTheme.card,
                        Color(red: 0.04, green: 0.14, blue: 0.32),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
    }
}

private enum DemoVideoCatalog {
    static let subdirectory = "SampleVideos"
    private static let supportedExtensions = ["mp4", "mov", "m4v"]

    static func url(for resourceName: String?, localPath: String?, remoteURL: String?) -> URL? {
        if let remoteURL, let url = URL(string: remoteURL) {
            return url
        }

        if let localPath, !localPath.isEmpty {
            let fileURL = URL(fileURLWithPath: localPath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        guard let resourceName, !resourceName.isEmpty else { return nil }
        let nsName = resourceName as NSString
        let ext = nsName.pathExtension
        let baseName = nsName.deletingPathExtension

        if !ext.isEmpty,
           let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: subdirectory) {
            return url
        }

        for ext in supportedExtensions {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }

        return nil
    }
}

private struct LoopingVideoSurface: View {
    let url: URL
    @StateObject private var playerStore = LoopingPlayerStore()

    var body: some View {
        LoopingPlayerLayerView(player: playerStore.player)
            .onAppear {
                playerStore.configure(url: url)
                playerStore.play()
            }
            .onDisappear {
                playerStore.pause()
            }
    }
}

private final class LoopingPlayerStore: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
    }

    func configure(url: URL) {
        guard currentURL != url else { return }
        currentURL = url
        looper = nil
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        self.layer as! AVPlayerLayer
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
        candidates: DemoData.candidates,
        likedCandidates: Array(DemoData.candidates.prefix(1)),
        availabilitySlots: [],
        approvals: [],
        onRefresh: {},
        onLikeCandidate: { _ in },
        onAddAvailabilitySlot: { _, _ in },
        onRespondToApproval: { _, _ in },
        onIssueReferral: { _ in },
        onShowNotifications: {},
        onSignOut: {}
    )
}
