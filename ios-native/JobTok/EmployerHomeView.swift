import SwiftUI
import PhotosUI
import CoreTransferable

struct EmployerHomeView: View {
    let profile: EmployerProfileDraft
    let accountEmail: String
    let jobs: [JobPostingRecord]
    let applications: [JobApplicationRecord]
    let discoverableCandidates: [DiscoverableCandidateRecord]
    let latestOutreachByCandidateID: [String: CandidateOutreachRecord]
    let onSaveProfile: (EmployerProfileDraft) -> Void
    let onCreateJob: (JobPostingDraft, URL) -> Void
    let onRefresh: () -> Void
    let onToggleJobPublishState: (String, Bool) -> Void
    let onReachOut: (String, String?, String, String) -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var workingProfile: EmployerProfileDraft
    @State private var selectedJobFunctionRawValue = "all"
    @State private var currentCandidateID: String?
    @State private var selectedCandidateForOutreach: DiscoverableCandidateRecord?
    @State private var isEditingProfile = false
    @State private var isCreatingJob = false
    @State private var showingSettingsDrawer = false
    @State private var showingDeleteAccountAlert = false
    @State private var selectedProfileTab: EmployerProfileTab = .videos

    init(
        profile: EmployerProfileDraft,
        accountEmail: String,
        jobs: [JobPostingRecord],
        applications: [JobApplicationRecord],
        discoverableCandidates: [DiscoverableCandidateRecord],
        latestOutreachByCandidateID: [String: CandidateOutreachRecord],
        onSaveProfile: @escaping (EmployerProfileDraft) -> Void,
        onCreateJob: @escaping (JobPostingDraft, URL) -> Void,
        onRefresh: @escaping () -> Void,
        onToggleJobPublishState: @escaping (String, Bool) -> Void,
        onReachOut: @escaping (String, String?, String, String) -> Void,
        onShowNotifications: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        self.profile = profile
        self.accountEmail = accountEmail
        self.jobs = jobs
        self.applications = applications
        self.discoverableCandidates = discoverableCandidates
        self.latestOutreachByCandidateID = latestOutreachByCandidateID
        self.onSaveProfile = onSaveProfile
        self.onCreateJob = onCreateJob
        self.onRefresh = onRefresh
        self.onToggleJobPublishState = onToggleJobPublishState
        self.onReachOut = onReachOut
        self.onShowNotifications = onShowNotifications
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _workingProfile = State(initialValue: profile)
    }

    private var selectedJobFunction: JobFunctionOption? {
        guard selectedJobFunctionRawValue != "all" else { return nil }
        return JobFunctionOption(rawValue: selectedJobFunctionRawValue)
    }

    private var filteredCandidates: [DiscoverableCandidateRecord] {
        discoverableCandidates.filter { candidate in
            guard let selectedJobFunction else { return true }
            return candidate.jobFunction == selectedJobFunction
        }
    }

    var body: some View {
        TabView {
            discoverView
                .tabItem {
                    Label("Discover", systemImage: "play.square.fill")
                }

            applicantsView
                .tabItem {
                    Label("Applicants", systemImage: "person.2.fill")
                }

            profileView
                .tabItem {
                    Label("Profile", systemImage: "building.2.crop.circle")
                }
        }
        .tint(PassportTheme.accent)
        .sheet(item: $selectedCandidateForOutreach) { candidate in
            EmployerOutreachSheet(
                candidate: candidate,
                jobs: jobs,
                latestOutreach: latestOutreachByCandidateID[candidate.id],
                onSend: { relatedJobID, subject, message in
                    onReachOut(candidate.id, relatedJobID, subject, message)
                    selectedCandidateForOutreach = nil
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isEditingProfile) {
            EmployerProfileEditor(profile: $workingProfile) {
                onSaveProfile(workingProfile)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isCreatingJob) {
            EmployerCreateJobSheet(
                profile: workingProfile,
                accountEmail: accountEmail,
                onCreateJob: onCreateJob
            )
            .presentationDetents([.large])
        }
        .onChange(of: profile) { _, newValue in
            workingProfile = newValue
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                showingSettingsDrawer = false
                onDeleteAccount()
            }
        } message: {
            Text("This permanently deletes your JobTok account and employer profile data.")
        }
    }

    private var discoverView: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let pageHeight = proxy.size.height + proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                if filteredCandidates.isEmpty {
                    EmployerEmptyStateView(
                        title: "No candidate videos yet",
                        message: discoverableCandidates.isEmpty
                            ? "Candidates who make themselves discoverable will appear here."
                            : "No candidates match the role filter you selected."
                    )
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredCandidates) { candidate in
                                EmployerCandidateFeedCard(
                                    candidate: candidate,
                                    latestOutreach: latestOutreachByCandidateID[candidate.id],
                                    isActive: currentCandidateID == candidate.id,
                                    onReachOut: {
                                        selectedCandidateForOutreach = candidate
                                    }
                                )
                                .frame(width: pageWidth, height: pageHeight)
                                .clipped()
                                .id(candidate.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentCandidateID)
                    .frame(width: pageWidth, height: pageHeight)
                    .offset(y: -proxy.safeAreaInsets.top)
                }

                discoverTopBar
                    .padding(.horizontal, 10)
                    .padding(.top, max(proxy.safeAreaInsets.top - 2, 0))
                    .offset(y: -24)
            }
            .onAppear {
                if currentCandidateID == nil {
                    currentCandidateID = filteredCandidates.first?.id
                }
            }
            .onChange(of: filteredCandidates.map(\.id)) { _, ids in
                guard let first = ids.first else {
                    currentCandidateID = nil
                    return
                }
                if let currentCandidateID, ids.contains(currentCandidateID) {
                    return
                }
                self.currentCandidateID = first
            }
        }
    }

    private var applicantsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Applicants",
                        subtitle: "Everyone who applied to your roles appears here with their saved pitch and resume snapshot."
                    )

                    if applications.isEmpty {
                        EmployerInfoCard(
                            title: "No applicants yet",
                            details: "Once candidates apply to your roles, their profile snapshot and pitch video will appear here."
                        )
                    } else {
                        ForEach(applications) { application in
                            EmployerApplicantCard(application: application)
                        }
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
        }
    }

    private var profileView: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        profileTopBar
                        employerProfileHero
                        employerProfileTabBar
                        employerProfileTabContent
                    }
                    .padding(20)
                }
                .background(PassportTheme.background)

                if showingSettingsDrawer {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showingSettingsDrawer = false
                            }
                        }

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        ProfileSettingsDrawer(
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    showingSettingsDrawer = false
                                }
                            },
                            onLogOut: {
                                showingSettingsDrawer = false
                                onSignOut()
                            },
                            onDeleteAccount: {
                                showingDeleteAccountAlert = true
                            }
                        )
                        .frame(width: 304)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                }
            }
        }
    }

    private var profileTopBar: some View {
        HStack {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text("Profile")
                .font(.headline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showingSettingsDrawer = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PassportTheme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(PassportTheme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(PassportTheme.border.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var employerProfileHero: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                Spacer()
                employerProfileAvatar
                Spacer()
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(workingProfile.companyName.isEmpty ? "Your Company" : workingProfile.companyName)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Button("Edit") {
                        isEditingProfile = true
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PassportTheme.card)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .clipShape(Capsule())
                }

                Text(employerIdentityText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textSecondary)

                Text(employerBioText)
                    .font(.body)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let companyURL = companyDomainURL {
                    HStack(spacing: 10) {
                        Link(destination: companyURL) {
                            Label(domainDisplayText, systemImage: "link")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(PassportTheme.card.opacity(0.96))
                                .foregroundStyle(PassportTheme.textSecondary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(PassportTheme.border.opacity(0.55), lineWidth: 1)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                employerProfileStat(title: "Jobs", value: "\(jobs.count)")
                employerProfileStat(title: "Live", value: "\(publishedJobsCount)")
                employerProfileStat(title: "Applicants", value: "\(applications.count)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .jobTokCard(cornerRadius: 30)
    }

    private var employerProfileTabBar: some View {
        HStack(spacing: 0) {
            ForEach(EmployerProfileTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedProfileTab = tab
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(tab.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedProfileTab == tab ? PassportTheme.textPrimary : PassportTheme.textSecondary)
                            .frame(maxWidth: .infinity)

                        Capsule()
                            .fill(selectedProfileTab == tab ? PassportTheme.accent : Color.clear)
                            .frame(height: 3)
                    }
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var employerProfileTabContent: some View {
        switch selectedProfileTab {
        case .videos:
            employerVideosTab
        case .about:
            employerAboutTab
        case .company:
            employerCompanyTab
        }
    }

    private var discoverTopBar: some View {
        HStack(spacing: 10) {
            Text("JobTok")
                .font(.headline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)

            Picker("Role filter", selection: $selectedJobFunctionRawValue) {
                Text("All").tag("all")
                ForEach(JobFunctionOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(PassportTheme.textPrimary)

            Spacer()

            HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
            HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .jobTokChromeCapsule()
    }

    private var employerVideosTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Role videos")
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text("Publish short-form hiring posts directly from your profile.")
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                Spacer()
                Button("Create Post") {
                    isCreatingJob = true
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }

            if jobs.isEmpty {
                EmployerInfoCard(
                    title: "No role videos yet",
                    details: "Upload your first hiring video and it will appear in the candidate feed after publishing."
                )
            } else {
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 12) {
                        RemoteVideoSurface(
                            urlString: job.videoURL,
                            isActive: true,
                            videoGravity: .resizeAspect,
                            autoPlay: false,
                            allowsTapToTogglePlayback: true,
                            showsPlayOverlayWhenPaused: true
                        )
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text(job.title)
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text("\(job.companyName) • \(job.location ?? "Remote")")
                            .foregroundStyle(PassportTheme.textSecondary)

                        Text(job.description)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .lineLimit(3)

                        HStack {
                            statusPill(title: job.isPublished ? "Published" : "Draft", isEmphasized: job.isPublished)
                            if let jobFunction = job.jobFunction {
                                statusPill(title: jobFunction.title, isEmphasized: false)
                            }
                            Spacer()
                            Button(job.isPublished ? "Unpublish" : "Publish") {
                                onToggleJobPublishState(job.id, !job.isPublished)
                            }
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(PassportTheme.card)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(20)
                    .jobTokCard(cornerRadius: 28)
                }
            }
        }
    }

    private var employerAboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("About")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Button("Edit") {
                    isEditingProfile = true
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                employerMetaRow(title: "Team", value: workingProfile.fullName.isEmpty ? "Add your hiring contact name" : workingProfile.fullName)
                employerMetaRow(title: "Headline", value: workingProfile.headline.isEmpty ? "Add a short employer headline" : workingProfile.headline)
                employerMetaRow(title: "Hiring for", value: workingProfile.positionTitle.isEmpty ? "Add your primary hiring focus" : workingProfile.positionTitle)
                employerMetaRow(title: "Email", value: accountEmail)
                employerMetaRow(title: "Role", value: "Employer")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .jobTokCard(cornerRadius: 28)
    }

    private var employerCompanyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Company")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Button("Edit") {
                    isEditingProfile = true
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                employerMetaRow(title: "Company", value: workingProfile.companyName.isEmpty ? "Add your company name" : workingProfile.companyName)
                employerMetaRow(title: "Domain", value: domainDisplayText)
                employerMetaRow(title: "Open roles", value: "\(publishedJobsCount) live • \(draftJobsCount) draft")
            }
            .padding(20)
            .jobTokCard(cornerRadius: 28)
        }
    }

    private var publishedJobsCount: Int {
        jobs.filter(\.isPublished).count
    }

    private var draftJobsCount: Int {
        jobs.count - publishedJobsCount
    }

    private var employerIdentityText: String {
        let name = workingProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = workingProfile.positionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name.isEmpty, focus.isEmpty) {
        case (false, false):
            return "\(name) • \(focus)"
        case (false, true):
            return name
        case (true, false):
            return focus
        case (true, true):
            return "Employer"
        }
    }

    private var employerBioText: String {
        let headline = workingProfile.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !headline.isEmpty {
            return headline
        }
        if !workingProfile.positionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Hiring for \(workingProfile.positionTitle) at \(workingProfile.companyName.isEmpty ? "your company" : workingProfile.companyName)."
        }
        return "Build a hiring profile that feels like a creator page for your company and open roles."
    }

    private var domainDisplayText: String {
        let trimmed = workingProfile.companyDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Add your website or domain" : trimmed
    }

    private var companyDomainURL: URL? {
        let trimmed = workingProfile.companyDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: normalized)
    }

    private var employerProfileAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PassportTheme.accent, PassportTheme.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 108, height: 108)

            Text(employerInitials)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 100, height: 100)
                .background(PassportTheme.accent)
                .clipShape(Circle())
        }
    }

    private var employerInitials: String {
        let source = workingProfile.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? workingProfile.fullName
            : workingProfile.companyName
        let parts = source
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let value = parts.joined()
        return value.isEmpty ? "JT" : value.uppercased()
    }

    private func employerProfileStat(title: String, value: String) -> some View {
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

    private func employerMetaRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .foregroundStyle(PassportTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)
                Text(subtitle)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            Spacer()

            HeaderAction(symbol: "arrow.clockwise", action: onRefresh)
            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
            HeaderAction(symbol: "rectangle.portrait.and.arrow.right", action: onSignOut)
        }
    }

    private func statusPill(title: String, isEmphasized: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isEmphasized ? PassportTheme.accent : PassportTheme.card)
            .foregroundStyle(isEmphasized ? Color.black : PassportTheme.textPrimary)
            .clipShape(Capsule())
    }
}

private struct EmployerCandidateFeedCard: View {
    let candidate: DiscoverableCandidateRecord
    let latestOutreach: CandidateOutreachRecord?
    let isActive: Bool
    let onReachOut: () -> Void

    var body: some View {
        ZStack {
            RemoteVideoSurface(urlString: candidate.videoURL, isActive: isActive)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    if let jobFunction = candidate.jobFunction {
                        Text(jobFunction.title.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(PassportTheme.accentSoft.opacity(0.95))
                            .foregroundStyle(PassportTheme.accent)
                            .clipShape(Capsule())
                    }

                    Text(candidate.fullName ?? "Candidate")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)

                    if let headline = candidate.headline, !headline.isEmpty {
                        Text(headline)
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)
                    }

                    if let schoolName = candidate.schoolName, !schoolName.isEmpty {
                        Text(schoolName)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    if let dreamRole = candidate.dreamRole, !dreamRole.isEmpty {
                        Text("Dream role: \(dreamRole)")
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    if !candidate.previousEmployers.isEmpty {
                        Text("Previous employers: \(candidate.previousEmployers.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .lineLimit(3)
                    }

                    if let compensationRange = candidate.desiredCompensationRange, !compensationRange.isEmpty {
                        Text("Comp: \(compensationRange)")
                            .font(.subheadline)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    candidateLinksRow(
                        linkedInURLString: candidate.linkedInURL,
                        instagramUsername: candidate.instagramUsername,
                        tiktokUsername: candidate.tiktokUsername
                    )

                    if let latestOutreach {
                        Text("Last outreach: \(formattedDate(latestOutreach.createdAt))")
                            .font(.footnote)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    Button(action: onReachOut) {
                        Text(latestOutreach == nil ? "Reach Out" : "Reach Out Again")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 72)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func candidateLinksRow(
        linkedInURLString: String?,
        instagramUsername: String?,
        tiktokUsername: String?
    ) -> some View {
        let linkedInURL = linkedInURLString.flatMap(URL.init(string:))
        let normalizedInstagram = normalizeUsername(instagramUsername)
        let normalizedTikTok = normalizeUsername(tiktokUsername)

        if linkedInURL != nil || normalizedInstagram != nil || normalizedTikTok != nil {
            HStack(spacing: 8) {
                if let linkedInURL {
                    candidateLinkTag(title: "LinkedIn", url: linkedInURL)
                }
                if let normalizedInstagram, let url = URL(string: "https://instagram.com/\(normalizedInstagram)") {
                    candidateLinkTag(title: "@\(normalizedInstagram)", url: url)
                }
                if let normalizedTikTok, let url = URL(string: "https://www.tiktok.com/@\(normalizedTikTok)") {
                    candidateLinkTag(title: "@\(normalizedTikTok)", url: url)
                }
            }
        }
    }

    private func candidateLinkTag(title: String, url: URL) -> some View {
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

    private func normalizeUsername(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EmployerApplicantCard: View {
    let application: JobApplicationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if application.candidateVideoURL != nil {
                RemoteVideoSurface(
                    urlString: application.candidateVideoURL,
                    isActive: true,
                    videoGravity: .resizeAspect,
                    autoPlay: false,
                    allowsTapToTogglePlayback: true,
                    showsPlayOverlayWhenPaused: true
                )
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(application.candidateName)
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)

                if let headline = application.candidateHeadline, !headline.isEmpty {
                    Text(headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                }

                Text("\(application.jobTitle) • \(application.companyName)")
                    .foregroundStyle(PassportTheme.textSecondary)

                if let school = application.candidateSchoolName, !school.isEmpty {
                    Text("School: \(school)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let dreamRole = application.candidateDreamRole, !dreamRole.isEmpty {
                    Text("Dream role: \(dreamRole)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if !application.candidatePreviousEmployers.isEmpty {
                    Text("Previous employers: \(application.candidatePreviousEmployers.joined(separator: ", "))")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let compensationRange = application.candidateCompensationRange, !compensationRange.isEmpty {
                    Text("Comp: \(compensationRange)")
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                applicantLinksRow(
                    linkedInURLString: application.candidateLinkedInURL,
                    instagramUsername: application.candidateInstagramUsername,
                    tiktokUsername: application.candidateTiktokUsername
                )

                HStack {
                    applicationStatusPill(title: application.status.capitalized)
                    applicationStatusPill(title: application.emailDeliveryStatus.capitalized)
                }

                if let coverNote = application.coverNote, !coverNote.isEmpty {
                    Text("Cover note")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(coverNote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let resumeFileName = application.resumeFileName, !resumeFileName.isEmpty {
                    Text("Resume snapshot: \(resumeFileName)")
                        .foregroundStyle(PassportTheme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .jobTokCard(cornerRadius: 22)
    }

    private func applicationStatusPill(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func applicantLinksRow(
        linkedInURLString: String?,
        instagramUsername: String?,
        tiktokUsername: String?
    ) -> some View {
        let linkedInURL = linkedInURLString.flatMap(URL.init(string:))
        let normalizedInstagram = normalizeUsername(instagramUsername)
        let normalizedTikTok = normalizeUsername(tiktokUsername)

        if linkedInURL != nil || normalizedInstagram != nil || normalizedTikTok != nil {
            HStack(spacing: 8) {
                if let linkedInURL {
                    candidateLinkTag(title: "LinkedIn", url: linkedInURL)
                }
                if let normalizedInstagram, let url = URL(string: "https://instagram.com/\(normalizedInstagram)") {
                    candidateLinkTag(title: "@\(normalizedInstagram)", url: url)
                }
                if let normalizedTikTok, let url = URL(string: "https://www.tiktok.com/@\(normalizedTikTok)") {
                    candidateLinkTag(title: "@\(normalizedTikTok)", url: url)
                }
            }
        }
    }

    private func candidateLinkTag(title: String, url: URL) -> some View {
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

    private func normalizeUsername(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EmployerProfileEditor: View {
    @Binding var profile: EmployerProfileDraft
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var initialFullName = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fullNameField
                    field(title: "Headline", text: $profile.headline, axis: .vertical, placeholder: "Hiring manager, founder, recruiter...")
                    field(title: "Company name", text: $profile.companyName)
                    field(title: "Company domain", text: $profile.companyDomain, placeholder: "usejobtok.com")
                    field(title: "Hiring focus", text: $profile.positionTitle, placeholder: "Founding Engineer, Product Designer...")
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .onAppear {
                initialFullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .background(PassportTheme.background)
            .navigationTitle("Edit Employer Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmedFullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedFullName != initialFullName,
                           let fullNameLastChangedAt = profile.fullNameLastChangedAt,
                           let nextAllowedDate = Calendar.current.date(byAdding: .day, value: 7, to: fullNameLastChangedAt),
                           nextAllowedDate > .now {
                            validationMessage = "Full name can only be changed once every 7 days."
                            return
                        }
                        profile.fullName = trimmedFullName
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.accent)
                }
            }
        }
    }

    private var fullNameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Full name")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                if let fullNameLastChangedAt = profile.fullNameLastChangedAt {
                    Text(fullNameCooldownText(from: fullNameLastChangedAt))
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
            }

            TextField("Full name", text: $profile.fullName)
                .textFieldStyle(PassportTextFieldStyle())

            Text("Can be changed once every 7 days.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
    }

    private func field(title: String, text: Binding<String>, axis: Axis = .horizontal, placeholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField(placeholder ?? title, text: text, axis: axis)
                .textFieldStyle(PassportTextFieldStyle())
                .lineLimit(axis == .vertical ? 3...5 : 1...1)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
    }

    private func fullNameCooldownText(from date: Date) -> String {
        let nextAllowedDate = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
        if nextAllowedDate <= .now {
            return "Available now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Again \(formatter.localizedString(for: nextAllowedDate, relativeTo: .now))"
    }
}

private struct EmployerCreateJobSheet: View {
    let profile: EmployerProfileDraft
    let accountEmail: String
    let onCreateJob: (JobPostingDraft, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = JobPostingDraft()
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var videoName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field(title: "Job title", text: $draft.title)
                    field(title: "Company name", text: $draft.companyName)
                    field(title: "Location", text: $draft.location)
                    compensationFields

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Job function")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Picker("Job function", selection: $draft.jobFunction) {
                            ForEach(JobFunctionOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    field(title: "Application email", text: $draft.applicationEmail)
                    field(title: "Source URL (optional)", text: $draft.sourceURL)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Description")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextField("Describe the opening", text: $draft.description, axis: .vertical)
                            .lineLimit(5...8)
                            .textFieldStyle(PassportTextFieldStyle())
                    }

                    Toggle(isOn: $draft.isPublished) {
                        Text("Publish immediately")
                            .foregroundStyle(PassportTheme.textPrimary)
                    }
                    .tint(PassportTheme.accent)

                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedVideoURL == nil ? "Upload role video" : "Role video selected")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)
                            Text(selectedVideoURL == nil ? "Choose the short-form job clip to publish." : videoName)
                                .font(.footnote)
                                .foregroundStyle(PassportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(PassportTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        guard let selectedVideoURL else {
                            errorMessage = "Select a role video before publishing."
                            return
                        }
                        onCreateJob(draft, selectedVideoURL)
                        dismiss()
                    } label: {
                        Text("Create Job Video")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("New Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
        }
        .onAppear {
            draft.employerProfileID = ""
            draft.companyName = profile.companyName
            draft.applicationEmail = accountEmail
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadVideo(newItem)
            }
        }
        .alert("Issue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(PassportTextFieldStyle())
                .lineLimit(1...4)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
    }

    private var compensationFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Annual pay (optional)")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 12) {
                field(title: "Min", text: $draft.compensationMinAnnual)
                field(title: "Max", text: $draft.compensationMaxAnnual)
            }

            Text("Enter whole numbers only, for example 120000.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
    }

    @MainActor
    private func loadVideo(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: EmployerSelectedMovie.self) else {
                errorMessage = "The selected video could not be loaded."
                return
            }
            selectedVideoURL = movie.url
            videoName = movie.fileName
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum EmployerProfileTab: String, CaseIterable, Identifiable {
    case videos
    case about
    case company

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos:
            return "Videos"
        case .about:
            return "About"
        case .company:
            return "Company"
        }
    }
}

private struct EmployerInfoCard: View {
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

private struct EmployerEmptyStateView: View {
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

private struct EmployerSelectedMovie: Transferable {
    let url: URL
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let temporaryDirectory = URL(filePath: NSTemporaryDirectory())
            let copiedURL = temporaryDirectory.appending(path: received.file.lastPathComponent)

            if FileManager.default.fileExists(atPath: copiedURL.path) {
                try FileManager.default.removeItem(at: copiedURL)
            }

            try FileManager.default.copyItem(at: received.file, to: copiedURL)
            return EmployerSelectedMovie(url: copiedURL, fileName: received.file.lastPathComponent)
        }
    }
}

private struct EmployerOutreachSheet: View {
    let candidate: DiscoverableCandidateRecord
    let jobs: [JobPostingRecord]
    let latestOutreach: CandidateOutreachRecord?
    let onSend: (String?, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRelatedJobID = ""
    @State private var subject = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EmployerInfoCard(
                        title: candidate.fullName ?? "Candidate",
                        details: [
                            candidate.headline,
                            candidate.dreamRole.map { "Dream role: \($0)" },
                            candidate.schoolName.map { "School: \($0)" }
                        ]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                    )

                    if let latestOutreach {
                        EmployerInfoCard(
                            title: "Latest outreach",
                            details: "\(latestOutreach.subject)\nSent \(formattedDate(latestOutreach.createdAt)) • \(latestOutreach.deliveryStatus.capitalized)"
                        )
                    }

                    if !jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Related job (optional)")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            Picker("Related job", selection: $selectedRelatedJobID) {
                                Text("None").tag("")
                                ForEach(jobs) { job in
                                    Text("\(job.title) • \(job.companyName)").tag(job.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(PassportTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(18)
                        .jobTokCard(cornerRadius: 22)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Subject")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextField("Subject", text: $subject)
                            .textFieldStyle(PassportTextFieldStyle())

                        Text("Message")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        TextEditor(text: $message)
                            .frame(minHeight: 180)
                            .padding(12)
                            .background(PassportTheme.card)
                            .foregroundStyle(PassportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(18)
                    .jobTokCard(cornerRadius: 22)

                    Button {
                        let relatedJobID = selectedRelatedJobID.isEmpty ? nil : selectedRelatedJobID
                        onSend(relatedJobID, subject.trimmingCharacters(in: .whitespacesAndNewlines), message.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } label: {
                        Text("Send Outreach")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("Reach Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
            .onAppear {
                if let firstJob = jobs.first {
                    selectedRelatedJobID = firstJob.id
                }
                subject = defaultSubject
                message = defaultMessage
            }
        }
    }

    private var defaultSubject: String {
        if let dreamRole = candidate.dreamRole, !dreamRole.isEmpty {
            return "Opportunity for \(dreamRole)"
        }
        return "Opportunity from JobTok"
    }

    private var defaultMessage: String {
        let name = candidate.fullName ?? "there"
        if let relatedJob = jobs.first(where: { $0.id == selectedRelatedJobID }) {
            return "Hi \(name),\n\nI came across your JobTok profile and think you could be a strong fit for our \(relatedJob.title) role at \(relatedJob.companyName). If you’re interested, reply and we can continue the conversation.\n"
        }
        return "Hi \(name),\n\nI came across your JobTok profile and wanted to reach out about opportunities on our team. If you’re interested, reply and we can continue the conversation.\n"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
