import SwiftUI

// TODO(deferred): Employer view refactor. ~1,340-line God-view with the same
// smell the candidate side had before its split. Same treatment: extract
// sheets/rows into their own files and move direct networking behind the
// service layer (mirror the JobSeekerHomeView / SupabaseService split).
// Off the candidate path, so deferred. Effort: large. See docs/DEFERRED_WORK.md.
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
    // P2: patch an application's pipeline status / internal notes.
    let onUpdateApplication: (String, String?, String?) -> Void
    // P1: short-lived signed resume URL for an owned application.
    let onRequestResumeURL: (String) async throws -> URL
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var workingProfile: EmployerProfileDraft
    @State private var selectedJobFunctionRawValue = "all"
    @State private var currentCandidateID: String?
    @State private var selectedCandidateForOutreach: DiscoverableCandidateRecord?
    @State private var isEditingProfile = false
    @State private var notesEditorTarget: JobApplicationRecord?
    @State private var resumeErrorMessage: String?
    @State private var showingVideoStudio = false
    @State private var showingSettingsDrawer = false
    @State private var showingDeleteAccountAlert = false
    @State private var selectedProfileTab: EmployerProfileTab = .videos
    @State private var selectedManagedJob: JobPostingRecord?

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
        onUpdateApplication: @escaping (String, String?, String?) -> Void = { _, _, _ in },
        onRequestResumeURL: @escaping (String) async throws -> URL = { _ in throw SupabaseServiceError.invalidResponse },
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
        self.onUpdateApplication = onUpdateApplication
        self.onRequestResumeURL = onRequestResumeURL
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
        .fullScreenCover(isPresented: $showingVideoStudio) {
            Scout22EmployerRoleWorkflow(
                profile: workingProfile,
                accountEmail: accountEmail,
                onCancel: {
                    showingVideoStudio = false
                },
                onCreateJob: { draft, url in
                    onCreateJob(draft, url)
                    showingVideoStudio = false
                }
            )
            .preferredColorScheme(.light)
        }
        .sheet(item: $selectedManagedJob) { job in
            EmployerRoleVideoDetailSheet(
                job: job,
                onTogglePublishState: {
                    onToggleJobPublishState(job.id, !job.isPublished)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $notesEditorTarget) { application in
            ApplicationNotesSheet(
                application: application,
                onSave: { notes in
                    onUpdateApplication(application.id, nil, notes)
                    notesEditorTarget = nil
                }
            )
            .presentationDetents([.medium])
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
            Text("This permanently deletes your scout22 account and employer profile data.")
        }
    }

    private var discoverView: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let pageHeight = proxy.size.height + proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                if filteredCandidates.isEmpty {
                    FeedEmptyState(
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
                        InfoCard(
                            title: "No applicants yet",
                            details: "Once candidates apply to your roles, their profile snapshot and pitch video will appear here."
                        )
                    } else {
                        ForEach(applications) { application in
                            EmployerApplicantCard(
                                application: application,
                                onUpdateStatus: { status in
                                    onUpdateApplication(application.id, status, nil)
                                },
                                onEditNotes: { notesEditorTarget = application },
                                onOpenResume: {
                                    Task {
                                        do {
                                            // AUDIT P1-4: failures (expired
                                            // session, 403, network) used to
                                            // be silently swallowed here.
                                            let url = try await onRequestResumeURL(application.id)
                                            await UIApplication.shared.open(url)
                                        } catch {
                                            resumeErrorMessage = SupabaseErrorMapping.friendlyMessage(for: error)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .alert("Couldn't open resume", isPresented: Binding(
                get: { resumeErrorMessage != nil },
                set: { newValue in
                    if !newValue { resumeErrorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resumeErrorMessage ?? "")
            }
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
                ProfileStatCell(title: "Jobs", value: "\(jobs.count)")
                ProfileStatCell(title: "Live", value: "\(publishedJobsCount)")
                ProfileStatCell(title: "Applicants", value: "\(applications.count)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .scout22Card(cornerRadius: 30)
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
            Text("scout22")
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
        .scout22ChromeCapsule()
    }

    private var employerVideosTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                Button {
                    showingVideoStudio = true
                } label: {
                    EmployerAddVideoTile()
                }
                .buttonStyle(.plain)

                ForEach(jobs) { job in
                    Button {
                        selectedManagedJob = job
                    } label: {
                        EmployerRoleVideoTile(job: job)
                    }
                    .buttonStyle(.plain)
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
        .scout22Card(cornerRadius: 28)
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
            .scout22Card(cornerRadius: 28)
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

    @State private var isMuted = false

    var body: some View {
        ZStack {
            RemoteVideoSurface(
                urlString: candidate.videoURL,
                isActive: isActive,
                allowsTapToTogglePlayback: true,
                showsPlayOverlayWhenPaused: true,
                isMuted: isMuted
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.90)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HStack(alignment: .bottom, spacing: 0) {
                    // Left: candidate info
                    VStack(alignment: .leading, spacing: 10) {
                        if let jobFunction = candidate.jobFunction {
                            feedTag(jobFunction.title.uppercased(), accent: true)
                        }

                        Text(candidate.fullName ?? "Candidate")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)

                        if let headline = candidate.headline, !headline.isEmpty {
                            Text(headline)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        if let school = candidate.schoolName, !school.isEmpty {
                            Label(school, systemImage: "building.columns")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        if !candidate.previousEmployers.isEmpty {
                            Text(candidate.previousEmployers.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }

                        if let comp = candidate.desiredCompensationRange, !comp.isEmpty {
                            feedTag(comp, accent: false)
                        }

                        SocialLinksRow(
                            linkedInURLString: candidate.linkedInURL,
                            instagramUsername: candidate.instagramUsername,
                            tiktokUsername: candidate.tiktokUsername
                        )

                        if let latestOutreach {
                            Text("Last contact \(relativeDate(latestOutreach.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Button(action: onReachOut) {
                            Text(latestOutreach == nil ? "Reach Out" : "Reach Out Again")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(PassportTheme.accent)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.trailing, 14)

                    // Right: action column (TikTok-style)
                    VStack(spacing: 18) {
                        FeedActionButton(
                            symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: isMuted ? "Muted" : "Sound",
                            action: { isMuted.toggle() }
                        )
                    }
                    .frame(width: 56)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 84)
            }
        }
    }

    private func feedTag(_ title: String, accent: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(accent ? 0.8 : 0)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent ? PassportTheme.accentSoft.opacity(0.95) : Color.black.opacity(0.45))
            .foregroundStyle(accent ? PassportTheme.accent : .white)
            .clipShape(Capsule())
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct EmployerApplicantCard: View {
    let application: JobApplicationRecord
    let onUpdateStatus: (String) -> Void
    let onEditNotes: () -> Void
    let onOpenResume: () -> Void

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

                SocialLinksRow(
                    linkedInURLString: application.candidateLinkedInURL,
                    instagramUsername: application.candidateInstagramUsername,
                    tiktokUsername: application.candidateTiktokUsername
                )

                HStack {
                    // P2: pipeline status menu — submitted renders as "New".
                    Menu {
                        ForEach(ApplicationStatus.allCases) { option in
                            Button(option.title) {
                                onUpdateStatus(option.rawValue)
                            }
                        }
                    } label: {
                        applicationStatusPill(title: ApplicationStatus(rawValue: application.status)?.title ?? application.status.capitalized)
                    }
                    applicationStatusPill(title: application.emailDeliveryStatus.capitalized)

                    Spacer()

                    Button {
                        onEditNotes()
                    } label: {
                        Image(systemName: (application.internalNotes ?? "").isEmpty ? "note.text.badge.plus" : "note.text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PassportTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                if let coverNote = application.coverNote, !coverNote.isEmpty {
                    Text("Cover note")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(coverNote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if let resumeFileName = application.resumeFileName, !resumeFileName.isEmpty {
                    Button {
                        onOpenResume()
                    } label: {
                        Label(resumeFileName, systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PassportTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .scout22Card(cornerRadius: 22)
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
        .scout22Card(cornerRadius: 22)
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
        .scout22Card(cornerRadius: 22)
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

private struct EmployerAddVideoTile: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PassportTheme.textPrimary)
            Text("Add Role")
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct EmployerRoleVideoTile: View {
    let job: JobPostingRecord

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteVideoSurface(
                urlString: job.videoURL,
                isActive: false,
                videoGravity: .resizeAspectFill,
                autoPlay: false,
                allowsTapToTogglePlayback: false,
                showsPlayOverlayWhenPaused: false
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(job.isPublished ? "Published" : "Draft")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(job.isPublished ? PassportTheme.accent : Color.white.opacity(0.14))
                        .foregroundStyle(job.isPublished ? .black : .white)
                        .clipShape(Capsule())

                    if let employmentType = job.employmentType {
                        Text(employmentType.title)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct EmployerRoleVideoDetailSheet: View {
    let job: JobPostingRecord
    let onTogglePublishState: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteVideoSurface(
                        urlString: job.videoURL,
                        isActive: true,
                        videoGravity: .resizeAspect,
                        autoPlay: false,
                        allowsTapToTogglePlayback: true,
                        showsPlayOverlayWhenPaused: true
                    )
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(job.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text("\(job.companyName) • \(job.location ?? "Remote")")
                            .foregroundStyle(PassportTheme.textSecondary)

                        HStack(spacing: 8) {
                            if let jobFunction = job.jobFunction {
                                Text(jobFunction.title)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(PassportTheme.card)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                    .clipShape(Capsule())
                            }
                            if let employmentType = job.employmentType {
                                Text(employmentType.title)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(PassportTheme.card)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                    .clipShape(Capsule())
                            }
                            if let compensationText {
                                Text(compensationText)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(PassportTheme.card)
                                    .foregroundStyle(PassportTheme.textPrimary)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("JD")
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)

                        Text(job.description)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .padding(20)
                    .scout22Card(cornerRadius: 28)

                    Button(job.isPublished ? "Unpublish Post" : "Publish Post") {
                        onTogglePublishState()
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(job.isPublished ? PassportTheme.card : PassportTheme.accent)
                    .foregroundStyle(job.isPublished ? PassportTheme.textPrimary : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
            }
            .background(PassportTheme.background)
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.textSecondary)
                }
            }
        }
    }

    private var compensationText: String? { job.compensationSummary }

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
                    InfoCard(
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
                        InfoCard(
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
                        .scout22Card(cornerRadius: 22)
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
                    .scout22Card(cornerRadius: 22)

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
        return "Opportunity from scout22"
    }

    private var defaultMessage: String {
        let name = candidate.fullName ?? "there"
        if let relatedJob = jobs.first(where: { $0.id == selectedRelatedJobID }) {
            return "Hi \(name),\n\nI came across your scout22 profile and think you could be a strong fit for our \(relatedJob.title) role at \(relatedJob.companyName). If you’re interested, reply and we can continue the conversation.\n"
        }
        return "Hi \(name),\n\nI came across your scout22 profile and wanted to reach out about opportunities on our team. If you’re interested, reply and we can continue the conversation.\n"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - P2 application pipeline

enum ApplicationStatus: String, CaseIterable, Identifiable {
    case submitted
    case reviewing
    case contacted
    case rejected
    case hired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .submitted: return "New"
        case .reviewing: return "Reviewing"
        case .contacted: return "Contacted"
        case .rejected: return "Rejected"
        case .hired: return "Hired"
        }
    }
}

/// Optional private notes per application — the employer-side feedback loop.
private struct ApplicationNotesSheet: View {
    let application: JobApplicationRecord
    let onSave: (String) -> Void
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(application: JobApplicationRecord, onSave: @escaping (String) -> Void) {
        self.application = application
        self.onSave = onSave
        _notes = State(initialValue: application.internalNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Internal notes — only your team sees these.")
                    .font(.footnote)
                    .foregroundStyle(PassportTheme.textSecondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(PassportTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
            }
            .padding(18)
            .background(PassportTheme.background)
            .navigationTitle("Notes · \(application.candidateName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(notes) }
                        .font(.subheadline.weight(.bold))
                }
            }
        }
    }
}
