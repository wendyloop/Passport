import SwiftUI
import PhotosUI
import AVFoundation
import SafariServices
import UIKit
import UniformTypeIdentifiers

struct JobSeekerHomeView: View {
    let profile: CandidateProfileDraft
    let jobs: [JobPostingRecord]
    let savedJobs: [JobPostingRecord]
    let savedJobIDs: Set<String>
    let applications: [JobApplicationRecord]
    let session: AuthSession?
    let onSaveProfile: (CandidateProfileDraft) -> Void
    let onUploadAvatar: (Data) -> Void
    let onUploadResume: (URL) -> Void
    let onUploadVideo: (URL, Double) -> Void
    let onRequestResumePreview: () async throws -> URL?
    let onApply: (JobApplicationDraft) -> Void
    let onToggleSavedJob: (String) -> Void
    let onRefresh: () -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var workingProfile: CandidateProfileDraft
    @State private var isEditingProfile = false
    @State private var showingResumeImporter = false
    @State private var showingVideoStudio = false
    @State private var importErrorMessage: String?
    @State private var currentJobID: String?
    @State private var applyingJob: JobPostingRecord?
    @State private var applyDrawerJob: JobPostingRecord?
    @State private var applicationDraft = JobApplicationDraft()
    @State private var easyApplyConfirmation: JobPostingRecord?
    @State private var founderEmailJob: JobPostingRecord?
    // Double-tap-to-save heart burst (TikTok like gesture).
    @State private var heartBurstJobID: String?
    @State private var heartBurstCount = 0
    @State private var easyApplySuccess: String?
    @State private var brokenJobIDs: Set<String> = []
    @State private var showingSettingsDrawer = false
    @State private var showingDeleteAccountAlert = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var resumePreviewURL: URL?
    @State private var selectedLocation = "all"
    @State private var selectedJobFunctionRawValue = "all"
    @State private var selectedPayFilter: JobPayFilter = .all
    @State private var selectedProfileTab: CandidateProfileTab = .video
    @State private var profileEditorTarget: CandidateProfileEditTarget?
    @State private var pendingVisibilityChange: CandidateVisibility?

    init(
        profile: CandidateProfileDraft,
        jobs: [JobPostingRecord],
        savedJobs: [JobPostingRecord],
        savedJobIDs: Set<String>,
        applications: [JobApplicationRecord],
        session: AuthSession? = nil,
        onSaveProfile: @escaping (CandidateProfileDraft) -> Void,
        onUploadAvatar: @escaping (Data) -> Void,
        onUploadResume: @escaping (URL) -> Void,
        onUploadVideo: @escaping (URL, Double) -> Void,
        onRequestResumePreview: @escaping () async throws -> URL?,
        onApply: @escaping (JobApplicationDraft) -> Void,
        onToggleSavedJob: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onShowNotifications: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        self.profile = profile
        self.jobs = jobs
        self.savedJobs = savedJobs
        self.savedJobIDs = savedJobIDs
        self.applications = applications
        self.session = session
        self.onSaveProfile = onSaveProfile
        self.onUploadAvatar = onUploadAvatar
        self.onUploadResume = onUploadResume
        self.onUploadVideo = onUploadVideo
        self.onRequestResumePreview = onRequestResumePreview
        self.onApply = onApply
        self.onToggleSavedJob = onToggleSavedJob
        self.onRefresh = onRefresh
        self.onShowNotifications = onShowNotifications
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _workingProfile = State(initialValue: profile)
    }

    private var appliedJobIDs: Set<String> {
        Set(applications.map(\.jobID))
    }

    private var profileNeedsSetup: Bool {
        workingProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || workingProfile.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || workingProfile.resumeFileName == nil
    }

    private var selectedJobFunction: JobFunctionOption? {
        guard selectedJobFunctionRawValue != "all" else { return nil }
        return JobFunctionOption(rawValue: selectedJobFunctionRawValue)
    }

    private var locationOptions: [String] {
        let values = Set(
            jobs.compactMap { job in
                let trimmed = job.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        return values.sorted()
    }

    // TODO(deferred): Feature backlog D1 + D3 — add experience_level /
    // work_mode filter chips (columns exist as of carousel v3) and a
    // startup-stage "founder-reachable" toggle (pre-seed→series B).
    // See docs/DEFERRED_WORK.md (Feature backlog).
    private var filteredJobs: [JobPostingRecord] {
        jobs.filter { job in
            let locationMatches: Bool = {
                guard selectedLocation != "all" else { return true }
                return (job.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == selectedLocation
            }()

            let functionMatches: Bool = {
                guard let selectedJobFunction else { return true }
                return job.jobFunction == selectedJobFunction
            }()

            let payMatches = selectedPayFilter.matches(job)
            // Carousel-backed rows (ATS + board) need at least one slide this
            // build can draw. No carousel yet (generate-carousel hasn't run) or
            // a carousel made entirely of unknown slide types → nothing to
            // render, so hide it.
            let renderable = !job.sourceKind.rendersCarousel || (job.carousel?.hasRenderableSlides ?? false)
            return renderable && !brokenJobIDs.contains(job.id) && locationMatches && functionMatches && payMatches
        }
    }

    // TikTok-style navigation: full-bleed content with a custom dark bar and
    // a prominent center record button — recording a pitch is the app's
    // centerpiece action, exactly like TikTok's create button.
    enum CandidateTab {
        case jobs, saved, applications, profile
    }

    @State private var selectedTab: CandidateTab = .jobs

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .jobs:
                    jobsFeed
                case .saved:
                    savedTabView
                case .applications:
                    applicationsView
                case .profile:
                    profileView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            candidateTabBar
        }
        .tint(PassportTheme.accent)
        .sheet(isPresented: $isEditingProfile) {
            CandidateProfileEditor(
                profile: $workingProfile,
                initialTarget: profileEditorTarget,
                onSave: {
                    onSaveProfile(workingProfile)
                }
            )
            .presentationDetents([.large])
            .onDisappear {
                profileEditorTarget = nil
            }
        }
        .sheet(item: $applyingJob) { job in
            ApplySheet(
                job: job,
                draft: $applicationDraft,
                onApply: {
                    onApply(applicationDraft)
                    applicationDraft = JobApplicationDraft()
                    applyingJob = nil
                }
            )
        }
        .sheet(item: $applyDrawerJob) { job in
            if let session {
                ApplyDrawerView(job: job, session: session, service: SupabaseService.shared.candidate, isPresented: Binding(
                    get: { applyDrawerJob != nil },
                    set: { if !$0 { applyDrawerJob = nil } }
                ))
            }
        }
        .sheet(item: $easyApplyConfirmation) { job in
            EasyApplyConfirmationSheet(
                job: job,
                resumeFileName: workingProfile.resumeFileName ?? "",
                onConfirm: {
                    let draft = makeApplicationDraft(for: job)
                    onApply(draft)
                    easyApplyConfirmation = nil
                    easyApplySuccess = job.title
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        easyApplySuccess = nil
                    }
                },
                onAdvanced: {
                    applicationDraft = makeApplicationDraft(for: job)
                    easyApplyConfirmation = nil
                    applyingJob = job
                }
            )
            .presentationDetents([.height(320)])
        }
        .sheet(item: $founderEmailJob) { job in
            if let session {
                FounderEmailSheet(
                    job: job,
                    session: session,
                    onRecordPitch: { showingVideoStudio = true },
                    onFallbackApply: { handleApplyTap(for: job) }
                )
                .presentationDetents([.large])
            }
        }
        .overlay(alignment: .top) {
            if let title = easyApplySuccess {
                EasyApplySuccessBanner(jobTitle: title)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: easyApplySuccess)
            }
        }
        .animation(.spring(response: 0.4), value: easyApplySuccess)
        .fullScreenCover(isPresented: $showingVideoStudio) {
            JobTokVideoStudio(
                purpose: .candidatePitch,
                startMode: .library,
                onCancel: {
                    showingVideoStudio = false
                },
                onComplete: { composedVideo in
                    acceptComposedVideo(composedVideo)
                    showingVideoStudio = false
                }
            )
        }
        .fileImporter(
            isPresented: $showingResumeImporter,
            allowedContentTypes: supportedResumeTypes,
            allowsMultipleSelection: false
        ) { result in
            handleResumeImport(result: result)
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handleAvatarSelection(item: newItem)
            }
        }
        .onChange(of: profile) { _, newValue in
            workingProfile = newValue
        }
        .alert("Import issue", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                showingSettingsDrawer = false
                onDeleteAccount()
            }
        } message: {
            Text("This permanently deletes your scout22 account and profile data.")
        }
        .alert("Change visibility mode?", isPresented: Binding(
            get: { pendingVisibilityChange != nil },
            set: { newValue in
                if !newValue {
                    pendingVisibilityChange = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                pendingVisibilityChange = nil
            }
            Button("Change") {
                applyPendingVisibilityChange()
            }
        } message: {
            Text(visibilityChangeMessage(for: pendingVisibilityChange))
        }
        .sheet(item: Binding(
            get: { resumePreviewURL.map(PreviewURL.init) },
            set: { resumePreviewURL = $0?.url }
        )) { preview in
            SafariSheet(url: preview.url)
        }
    }

    private var jobsFeed: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let pageHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                if filteredJobs.isEmpty {
                    FeedEmptyState(
                        title: jobs.isEmpty ? "No jobs live yet" : "No jobs match your filters",
                        message: jobs.isEmpty
                            ? "Admins can publish the first scout22 openings from the admin portal."
                            : "Try widening your location, role type, or pay filters."
                    )
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredJobs) { job in
                                feedCard(
                                    job: job,
                                    pageWidth: pageWidth,
                                    pageHeight: pageHeight,
                                    safeAreaBottom: proxy.safeAreaInsets.bottom
                                )
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentJobID)
                    .frame(width: pageWidth, height: pageHeight)
                    .offset(y: -proxy.safeAreaInsets.top)
                }

                topBar
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            .onAppear {
                if currentJobID == nil {
                    currentJobID = filteredJobs.first?.id
                }
            }
            .onChange(of: filteredJobs.map(\.id)) { _, ids in
                guard let first = ids.first else {
                    currentJobID = nil
                    return
                }
                if let currentJobID, ids.contains(currentJobID) {
                    return
                }
                self.currentJobID = first
            }
        }
    }

    @ViewBuilder
    private func feedCard(
        job: JobPostingRecord,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        Group {
            // Carousel-backed rows (ATS + board) render the structured carousel;
            // reels + employer posts keep the existing video card. The filter
            // guarantees a carousel row reaching here has a non-nil carousel.
            if job.sourceKind.rendersCarousel, let carousel = job.carousel {
                CarouselFeedCard(
                    job: job,
                    carousel: carousel,
                    safeAreaBottom: safeAreaBottom,
                    isActive: currentJobID == job.id,
                    onApply: { handleApplyTap(for: job) },
                    onEmailFounder: job.companyID == nil ? nil : { handleEmailFounderTap(for: job) },
                    onSave: { onToggleSavedJob(job.id) },
                    isSaved: savedJobIDs.contains(job.id)
                )
            } else {
                JobFeedCard(
                    job: job,
                    safeAreaBottom: safeAreaBottom,
                    alreadyApplied: appliedJobIDs.contains(job.id),
                    isSaved: savedJobIDs.contains(job.id),
                    isActive: currentJobID == job.id,
                    onToggleSaved: { onToggleSavedJob(job.id) },
                    onApply: { handleApplyTap(for: job) },
                    onEmailFounder: job.companyID == nil ? nil : { handleEmailFounderTap(for: job) },
                    onBroken: { brokenJobIDs.insert(job.id) }
                )
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .clipped()
        .overlay {
            if heartBurstJobID == job.id {
                HeartBurstView(trigger: heartBurstCount)
                    .allowsHitTesting(false)
            }
        }
        // Double tap saves, TikTok-style. High priority so it wins over the
        // video's single-tap play/pause (which now waits out the double-tap
        // window — same slight delay TikTok has).
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                handleDoubleTapSave(job)
            }
        )
        .id(job.id)
    }

    private func handleDoubleTapSave(_ job: JobPostingRecord) {
        // Double tap only ever saves — it never un-saves (matching TikTok,
        // where re-double-tapping shows the heart again but stays liked).
        if !savedJobIDs.contains(job.id) {
            onToggleSavedJob(job.id)
        }
        heartBurstJobID = job.id
        heartBurstCount += 1
    }

    private func handleApplyTap(for job: JobPostingRecord) {
        if job.canApplyViaDrawer {
            applyDrawerJob = job
        } else if workingProfile.resumeStoragePath != nil {
            easyApplyConfirmation = job
        } else {
            applicationDraft = makeApplicationDraft(for: job)
            applyingJob = job
        }
    }

    private func handleEmailFounderTap(for job: JobPostingRecord) {
        founderEmailJob = job
    }

    private var applicationsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Applications",
                        subtitle: "A cleaner inbox for every role you’ve sent."
                    )

                    if applications.isEmpty {
                        InfoCard(
                            title: "No applications yet",
                            details: "Apply to a job from the feed and it will appear here."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                                MinimalApplicationRow(application: application)

                                if index < applications.count - 1 {
                                    Divider()
                                        .overlay(PassportTheme.border.opacity(0.5))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .jobTokCard(cornerRadius: 28, fill: PassportTheme.surface)
                    }
                }
                .padding(20)
                .padding(.bottom, 84)
            }
            .background(PassportTheme.background)
        }
    }

    private var profileView: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        profileTopBar
                        candidateProfileHero
                        profileTabBar
                        profileTabContent
                    }
                    .padding(20)
                    .padding(.bottom, 84)
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

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("scout22")
                .font(.headline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("All locations") {
                            selectedLocation = "all"
                        }
                        ForEach(locationOptions, id: \.self) { location in
                            Button(location) {
                                selectedLocation = location
                            }
                        }
                    } label: {
                        filterPill(title: selectedLocation == "all" ? "Location" : selectedLocation)
                    }

                    Menu {
                        Button("All roles") {
                            selectedJobFunctionRawValue = "all"
                        }
                        ForEach(JobFunctionOption.allCases) { option in
                            Button(option.title) {
                                selectedJobFunctionRawValue = option.rawValue
                            }
                        }
                    } label: {
                        filterPill(title: selectedJobFunction?.title ?? "Role Type")
                    }

                    Menu {
                        ForEach(JobPayFilter.allCases) { option in
                            Button(option.title) {
                                selectedPayFilter = option
                            }
                        }
                    } label: {
                        filterPill(title: selectedPayFilter.title)
                    }
                }
            }

            Spacer(minLength: 0)

            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .jobTokChromeCapsule()
    }

    private func filterPill(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(PassportTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(PassportTheme.card)
        .clipShape(Capsule())
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(subtitle)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                Spacer()
                HeaderAction(symbol: "bell.fill", action: onShowNotifications)
            }
        }
    }

    private var candidateProfileHero: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                Spacer()
                profileAvatar
                Spacer()
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(workingProfile.fullName.isEmpty ? "Your Name" : workingProfile.fullName)
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

                Text(handleText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textSecondary)

                Text(bioText)
                    .font(.body)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if hasAnyProfileLink {
                    HStack(spacing: 10) {
                        if let linkedInURL {
                            profileLinkTag(title: "LinkedIn", url: linkedInURL)
                        }
                        if let instagramURL {
                            profileLinkTag(title: "@\(normalizedUsernameDisplay(workingProfile.instagramUsername))", url: instagramURL)
                        }
                        if let tiktokURL {
                            profileLinkTag(title: "@\(normalizedUsernameDisplay(workingProfile.tiktokUsername))", url: tiktokURL)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                ProfileStatCell(title: "Applied", value: "\(applications.count)")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedProfileTab = .about
                    }
                } label: {
                    ProfileStatCell(title: "Checklist", value: "\(completedChecklistCount)/5")
                }
                .buttonStyle(.plain)

                Button {
                    toggleVisibilityMode()
                } label: {
                    ProfileStatCell(title: "Mode", value: visibilityLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .jobTokCard(cornerRadius: 30)
    }

    private var profileTabBar: some View {
        HStack(spacing: 0) {
            ForEach(CandidateProfileTab.allCases) { tab in
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
    private var profileTabContent: some View {
        switch selectedProfileTab {
        case .video:
            profileVideoTab
        case .about:
            profileAboutTab
        case .saved:
            savedJobsTab
        }
    }

    private var profileVideoTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let videoURL = workingProfile.introVideoURL {
                RemoteVideoSurface(
                    urlString: videoURL,
                    isActive: true,
                    videoGravity: .resizeAspect,
                    autoPlay: false,
                    allowsTapToTogglePlayback: true,
                    showsPlayOverlayWhenPaused: true
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        showingVideoStudio = true
                    } label: {
                        Label("Update Video", systemImage: "video.badge.plus")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button("Edit Profile") {
                        isEditingProfile = true
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PassportTheme.card)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add your pitch video")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)

                    Text("This is the first thing employers see — and it unlocks direct founder intros from the feed.")
                        .foregroundStyle(PassportTheme.textSecondary)

                    Button {
                        showingVideoStudio = true
                    } label: {
                        Label("Upload Video", systemImage: "video.badge.plus")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("1:00 max")
                        .font(.footnote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                .padding(20)
                .jobTokCard(cornerRadius: 28)
            }
        }
    }

    private var profileAboutTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            checklistCard
            aboutSummaryCard
            visibilityModeCard
            profileAssetsCard
        }
    }

    private var savedTabView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Saved",
                        subtitle: "Roles you bookmarked from the feed."
                    )
                    savedJobsTab
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 96)
            }
            .background(PassportTheme.background)
        }
    }

    // MARK: - TikTok-style tab bar

    private var candidateTabBar: some View {
        HStack(alignment: .center, spacing: 0) {
            tabBarButton(.jobs, symbol: "play.square.fill", label: "Jobs")
            tabBarButton(.saved, symbol: "bookmark.fill", label: "Saved")

            // Center record button — opens the pitch video studio.
            Button {
                showingVideoStudio = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PassportTheme.accent)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .offset(x: -3)
                    )
            }
            .frame(maxWidth: .infinity)

            tabBarButton(.applications, symbol: "tray.full.fill", label: "Inbox")
            tabBarButton(.profile, symbol: "person.crop.circle.fill", label: "Me")
        }
        .padding(.top, 10)
        .padding(.bottom, 24)
        .padding(.horizontal, 6)
        .background(
            // Always-dark bar, TikTok-style, regardless of system theme. On
            // the feed it blends into the video; elsewhere it anchors the UI.
            Color.black.opacity(selectedTab == .jobs ? 0.35 : 0.96)
                .background(selectedTab == .jobs ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabBarButton(_ tab: CandidateTab, symbol: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var savedJobsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if savedJobs.isEmpty {
                InfoCard(
                    title: "No saved jobs yet",
                    details: "Save roles from the feed and they’ll show up here."
                )
            } else {
                ForEach(savedJobs) { job in
                    SavedJobCard(
                        job: job,
                        isApplied: appliedJobIDs.contains(job.id),
                        isSaved: savedJobIDs.contains(job.id),
                        onApply: {
                            if workingProfile.resumeStoragePath != nil {
                                easyApplyConfirmation = job
                            } else {
                                applicationDraft = makeApplicationDraft(for: job)
                                applyingJob = job
                            }
                        },
                        onToggleSaved: {
                            onToggleSavedJob(job.id)
                        }
                    )
                }
            }
        }
    }

    private var handleText: String {
        let raw = workingProfile.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return raw.hasPrefix("@") ? raw.lowercased() : "@\(raw.lowercased())"
        }

        let derived = workingProfile.fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        guard !derived.isEmpty else { return "@jobtok.creator" }
        return "@\(derived)"
    }

    private func makeApplicationDraft(for job: JobPostingRecord) -> JobApplicationDraft {
        JobApplicationDraft(
            jobID: job.id,
            resumeFileName: workingProfile.resumeFileName,
            resumeFilePath: workingProfile.resumeStoragePath,
            includePitchVideo: workingProfile.introVideoURL != nil,
            pitchVideoURL: workingProfile.introVideoURL,
            sharedSocialLink: defaultApplicationSocialLink
        )
    }

    private var defaultApplicationSocialLink: String {
        let linkedIn = workingProfile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !linkedIn.isEmpty {
            return linkedIn
        }

        let instagram = normalizedUsernameDisplay(workingProfile.instagramUsername)
        if !instagram.isEmpty {
            return "https://instagram.com/\(instagram)"
        }

        let tiktok = normalizedUsernameDisplay(workingProfile.tiktokUsername)
        if !tiktok.isEmpty {
            return "https://www.tiktok.com/@\(tiktok)"
        }

        return ""
    }

    private var visibilityLabel: String {
        switch workingProfile.visibility {
        case .appliedRolesOnly:
            return "Private"
        case .discoverableToHiringEmployers:
            return "Public"
        case .private:
            return "Private"
        }
    }

    private var linkedInURL: URL? {
        let value = workingProfile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : URL(string: value)
    }

    private var instagramURL: URL? {
        let username = normalizedUsernameDisplay(workingProfile.instagramUsername)
        guard !username.isEmpty else { return nil }
        return URL(string: "https://instagram.com/\(username)")
    }

    private var tiktokURL: URL? {
        let username = normalizedUsernameDisplay(workingProfile.tiktokUsername)
        guard !username.isEmpty else { return nil }
        return URL(string: "https://www.tiktok.com/@\(username)")
    }

    private var hasAnyProfileLink: Bool {
        linkedInURL != nil || instagramURL != nil || tiktokURL != nil
    }

    private var completedChecklistCount: Int {
        profileChecklistItems.filter(\.isComplete).count
    }

    private var profileChecklistItems: [ProfileChecklistItem] {
        [
            .init(title: "Profile photo", isComplete: workingProfile.avatarURL != nil, kind: .profilePhoto),
            .init(title: "Resume", isComplete: workingProfile.resumeStoragePath != nil, kind: .resume),
            .init(title: "Pitch video", isComplete: workingProfile.introVideoURL != nil, kind: .pitchVideo),
            .init(title: "LinkedIn", isComplete: !workingProfile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind: .linkedIn),
            .init(title: "TikTok / Instagram", isComplete: !workingProfile.instagramUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workingProfile.tiktokUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind: .professionalSocial)
        ]
    }

    private var compensationPreferenceText: String {
        let trimmed = workingProfile.desiredCompensationRange.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private var bioText: String {
        let trimmedHeadline = workingProfile.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHeadline.isEmpty {
            return trimmedHeadline
        }

        var parts: [String] = []
        if !workingProfile.dreamRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Working toward \(workingProfile.dreamRole).")
        }
        if !workingProfile.school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Studied at \(workingProfile.school).")
        }
        if !workingProfile.employers.isEmpty {
            parts.append("Experience at \(workingProfile.employers.joined(separator: ", ")).")
        }
        if parts.isEmpty {
            return "Write a short bio that explains what you do, what you want next, and why employers should keep watching."
        }
        return parts.joined(separator: " ")
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Checklist")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(completedChecklistCount)/5")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            ForEach(profileChecklistItems) { item in
                checklistItemRow(item)
            }
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
    }

    private var aboutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("About")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Button("Edit") {
                    openProfileEditor(target: .headline)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textSecondary)
            }

            Button {
                openProfileEditor(target: .headline)
            } label: {
                Text(bioText)
                    .foregroundStyle(PassportTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openProfileEditor(target: .jobFunction)
                } label: {
                    profileMetaRow(title: "Focus", value: workingProfile.jobFunction.title)
                }
                .buttonStyle(.plain)
                if !workingProfile.dreamRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .dreamRole)
                    } label: {
                        profileMetaRow(title: "Dream role", value: workingProfile.dreamRole)
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.desiredCompensationRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .compensation)
                    } label: {
                        profileMetaRow(title: "Comp", value: compensationPreferenceText)
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .linkedIn)
                    } label: {
                        profileMetaRow(title: "LinkedIn", value: workingProfile.linkedInURL)
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.instagramUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .instagram)
                    } label: {
                        profileMetaRow(title: "Instagram", value: "@\(normalizedUsernameDisplay(workingProfile.instagramUsername))")
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.tiktokUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .tiktok)
                    } label: {
                        profileMetaRow(title: "TikTok", value: "@\(normalizedUsernameDisplay(workingProfile.tiktokUsername))")
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openProfileEditor(target: .school)
                    } label: {
                        profileMetaRow(title: "School", value: workingProfile.school)
                    }
                    .buttonStyle(.plain)
                }
                if !workingProfile.employers.isEmpty {
                    Button {
                        openProfileEditor(target: .employers)
                    } label: {
                        profileMetaRow(title: "Experience", value: workingProfile.employers.joined(separator: ", "))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
    }

    private var visibilityModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mode")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Toggle(isOn: Binding(
                get: { workingProfile.visibility == .discoverableToHiringEmployers },
                set: { isOn in
                    pendingVisibilityChange = isOn ? .discoverableToHiringEmployers : .appliedRolesOnly
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workingProfile.visibility == .discoverableToHiringEmployers ? "Public mode" : "Private mode")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(workingProfile.visibility == .discoverableToHiringEmployers ? "All employers" : "Applied companies only")
                        .font(.footnote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
            }
            .tint(PassportTheme.accent)
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
    }

    private var profileAssetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assets")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 12) {
                Button {
                    showingResumeImporter = true
                } label: {
                    Label(workingProfile.resumeFileName == nil ? "Add Resume" : "Update Resume", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(PassportTheme.card)
                .foregroundStyle(PassportTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
                )

                Button {
                    showingVideoStudio = true
                } label: {
                    Label(workingProfile.introVideoFileName == nil ? "Add Video" : "Update Video", systemImage: "video.badge.plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if workingProfile.resumeStoragePath != nil {
                Button {
                    Task {
                        do {
                            resumePreviewURL = try await onRequestResumePreview()
                        } catch {
                            importErrorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("View Resume", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PassportTheme.card)
                        .foregroundStyle(PassportTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .jobTokCard(cornerRadius: 28)
    }

    @ViewBuilder
    private func checklistItemRow(_ item: ProfileChecklistItem) -> some View {
        switch item.kind {
        case .profilePhoto:
            PhotosPicker(
                selection: $selectedAvatarItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                checklistRowLabel(item)
            }
        case .resume:
            Button {
                showingResumeImporter = true
            } label: {
                checklistRowLabel(item)
            }
            .buttonStyle(.plain)
        case .pitchVideo:
            Button {
                showingVideoStudio = true
            } label: {
                checklistRowLabel(item)
            }
            .buttonStyle(.plain)
        case .linkedIn:
            Button {
                openProfileEditor(target: .linkedIn)
            } label: {
                checklistRowLabel(item)
            }
            .buttonStyle(.plain)
        case .professionalSocial:
            Button {
                openProfileEditor(target: .instagram)
            } label: {
                checklistRowLabel(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func checklistRowLabel(_ item: ProfileChecklistItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? PassportTheme.accent : PassportTheme.textMuted)
            Text(item.title)
                .foregroundStyle(PassportTheme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PassportTheme.textMuted)
        }
        .contentShape(Rectangle())
    }

    private func openProfileEditor(target: CandidateProfileEditTarget) {
        profileEditorTarget = target
        isEditingProfile = true
    }

    private func toggleVisibilityMode() {
        pendingVisibilityChange = workingProfile.visibility == .discoverableToHiringEmployers ? .appliedRolesOnly : .discoverableToHiringEmployers
    }

    private func applyPendingVisibilityChange() {
        guard let pendingVisibilityChange else { return }
        workingProfile.visibility = pendingVisibilityChange
        onSaveProfile(workingProfile)
        self.pendingVisibilityChange = nil
    }

    private func visibilityChangeMessage(for visibility: CandidateVisibility?) -> String {
        switch visibility {
        case .discoverableToHiringEmployers:
            return "Changing to Public will make your profile discoverable by all hiring employers."
        case .appliedRolesOnly, .private:
            return "Changing to Private will make your profile viewable only to employers you’ve applied to."
        case nil:
            return ""
        }
    }

    private var profileAvatar: some View {
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

            if let avatarURL = workingProfile.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarInitials
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
            } else {
                avatarInitials
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(
                selection: $selectedAvatarItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PassportTheme.textPrimary)
                    .padding(8)
                    .background(PassportTheme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(PassportTheme.border.opacity(0.7), lineWidth: 1))
            }
        }
    }

    private var avatarInitials: some View {
        Text(initialsText)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 100, height: 100)
            .background(PassportTheme.accent)
            .clipShape(Circle())
    }

    private var initialsText: String {
        let components = workingProfile.fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
        return components.isEmpty ? "JT" : components.joined()
    }

    private func profileLinkTag(title: String, url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: "at")
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

    private func normalizedUsernameDisplay(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
    }

    private func profileMetaRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .foregroundStyle(PassportTheme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func toolkitRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PassportTheme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var supportedResumeTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        return types
    }

    private func handleResumeImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard let copiedURL = copyImportedFileToTemporaryDirectory(from: url) else { return }
            workingProfile.resumeFileName = copiedURL.lastPathComponent
            workingProfile.resumeImportedAt = Date()
            onUploadResume(copiedURL)
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleAvatarSelection(item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.86)
            else {
                importErrorMessage = "The selected image could not be loaded."
                return
            }

            onUploadAvatar(jpegData)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func acceptComposedVideo(_ composedVideo: JobTokComposedVideo) {
        workingProfile.introVideoFileName = composedVideo.fileName
        workingProfile.introVideoDuration = composedVideo.duration
        onUploadVideo(composedVideo.url, composedVideo.duration)
    }

    private func formattedImportDate(_ date: Date?) -> String {
        guard let date else { return "just now" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyImportedFileToTemporaryDirectory(from url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destination = URL(filePath: NSTemporaryDirectory()).appending(path: url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            importErrorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct JobFeedCard: View {
    let job: JobPostingRecord
    let safeAreaBottom: CGFloat
    let alreadyApplied: Bool
    let isSaved: Bool
    let isActive: Bool
    let onToggleSaved: () -> Void
    let onApply: () -> Void
    let onEmailFounder: (() -> Void)?
    let onBroken: () -> Void

    @State private var isMuted = false

    private var canApply: Bool {
        !alreadyApplied && !job.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSocialEmbed: Bool {
        guard let url = job.videoURL, !url.isEmpty,
              let host = URL(string: url)?.host?.lowercased() else { return false }
        return host.contains("tiktok.com") || host.contains("instagram.com")
    }

    var body: some View {
        ZStack {
            RemoteVideoSurface(
                urlString: job.videoURL,
                isActive: isActive,
                allowsTapToTogglePlayback: true,
                showsPlayOverlayWhenPaused: true,
                isMuted: isMuted,
                onBroken: onBroken
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
                    // Left: job info
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            if let jobFunction = job.jobFunction {
                                feedTag(jobFunction.title.uppercased(), accent: true)
                            }
                            if let pay = compensationText {
                                feedTag(pay, accent: false)
                            }
                            if let type = job.employmentType {
                                feedTag(type.title, accent: false)
                            }
                        }

                        let genericNames: Set<String> = ["unknown", "tiktok", "instagram"]
                        if !job.companyName.isEmpty && !genericNames.contains(job.companyName.lowercased()) {
                            Text(job.companyName)
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }

                        HStack(spacing: 6) {
                            if let jobFunction = job.jobFunction {
                                Text(jobFunction.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            if let location = job.location, !location.isEmpty {
                                if job.jobFunction != nil {
                                    Text("·")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Label(location, systemImage: "mappin")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        Text(job.description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)

                        Button(action: onApply) {
                            Text(alreadyApplied ? "Already Applied" : (canApply ? "Apply Now" : "Apply Unavailable"))
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background((alreadyApplied || !canApply) ? Color.white.opacity(0.15) : PassportTheme.accent)
                                .foregroundStyle(alreadyApplied ? .white : .black)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(alreadyApplied || !canApply)

                        if let onEmailFounder {
                            Button(action: onEmailFounder) {
                                Label("Email the founder", systemImage: "envelope")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.trailing, 14)

                    // Right: action column (TikTok-style)
                    VStack(spacing: 18) {
                        FeedActionButton(
                            symbol: isSaved ? "bookmark.fill" : "bookmark",
                            isActive: isSaved,
                            label: "Save",
                            action: onToggleSaved
                        )
                        if !isSocialEmbed {
                            FeedActionButton(
                                symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                label: isMuted ? "Muted" : "Sound",
                                action: { isMuted.toggle() }
                            )
                        }
                    }
                    .frame(width: 56)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, safeAreaBottom + 20)
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

    private var compensationText: String? { job.compensationSummary }

}

private struct ApplySheet: View {
    let job: JobPostingRecord
    @Binding var draft: JobApplicationDraft
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var canApply: Bool {
        draft.resumeFilePath != nil
            && !job.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Easy Apply")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(job.companyName)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                if job.applicationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Applications are not available for this post yet. The admin still needs to add the company’s apply route.")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                applyAssetRow(
                    title: "Resume",
                    value: draft.resumeFileName ?? "Upload a resume in your profile first",
                    isRequired: true,
                    isSelected: draft.resumeFilePath != nil
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pitch video")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PassportTheme.textPrimary)
                            Text(draft.pitchVideoURL == nil ? "Optional. No pitch video on your profile yet." : "Optional. Share your current pitch video with this application.")
                                .font(.footnote)
                                .foregroundStyle(PassportTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { draft.includePitchVideo && draft.pitchVideoURL != nil },
                            set: { draft.includePitchVideo = $0 }
                        ))
                        .labelsHidden()
                        .disabled(draft.pitchVideoURL == nil)
                    }
                }
                .padding(16)
                .background(PassportTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Shared social link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    TextField("Paste LinkedIn, Instagram, or TikTok link", text: $draft.sharedSocialLink)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(PassportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("If it isn’t on your profile yet, scout22 will save it for next time.")
                        .font(.footnote)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                .padding(16)
                .background(PassportTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    guard canApply else { return }
                    onApply()
                    dismiss()
                } label: {
                    Text("Submit Application")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canApply)
                .opacity(canApply ? 1 : 0.5)

                Spacer()
            }
            .padding(20)
            .background(PassportTheme.background)
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

    @ViewBuilder
    private func applyAssetRow(title: String, value: String, isRequired: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? PassportTheme.accent : PassportTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    if isRequired {
                        Text("Required")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PassportTheme.accentSoft)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                }

                Text(value)
                    .font(.footnote)
                    .foregroundStyle(PassportTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CandidateProfileEditor: View {
    @Binding var profile: CandidateProfileDraft
    let initialTarget: CandidateProfileEditTarget?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var employersText = ""
    @State private var validationMessage: String?
    @State private var initialFullName = ""
    @State private var initialHandle = ""
    @State private var pendingVisibilityChange: CandidateVisibility?
    @FocusState private var focusedField: CandidateProfileEditTarget?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        fullNameField
                        handleField
                        headlineField
                        schoolField
                        employersField
                        dreamRoleField
                        compensationRangeField
                        linkedInField
                        socialUsernameField(title: "Instagram", text: $profile.instagramUsername, placeholder: "yourhandle", target: .instagram)
                        socialUsernameField(title: "TikTok", text: $profile.tiktokUsername, placeholder: "yourhandle", target: .tiktok)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Job function")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            Picker("Job function", selection: $profile.jobFunction) {
                                ForEach(JobFunctionOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 150)
                        }
                        .padding(18)
                        .jobTokCard(cornerRadius: 22)
                        .id(CandidateProfileEditTarget.jobFunction)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Visibility")
                                .font(.headline)
                                .foregroundStyle(PassportTheme.textPrimary)

                            Toggle(isOn: Binding(
                                get: { profile.visibility == .discoverableToHiringEmployers },
                                set: { isOn in
                                    pendingVisibilityChange = isOn ? .discoverableToHiringEmployers : .appliedRolesOnly
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.visibility == .discoverableToHiringEmployers ? "Public mode" : "Private mode")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(PassportTheme.textPrimary)
                                    Text(profile.visibility == .discoverableToHiringEmployers
                                         ? "All employers"
                                         : "Applied companies only")
                                        .font(.footnote)
                                        .foregroundStyle(PassportTheme.textSecondary)
                                }
                            }
                            .tint(PassportTheme.accent)
                        }
                        .padding(18)
                        .jobTokCard(cornerRadius: 22)

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(20)
                }
                .alert("Change visibility mode?", isPresented: Binding(
                    get: { pendingVisibilityChange != nil },
                    set: { newValue in
                        if !newValue {
                            pendingVisibilityChange = nil
                        }
                    }
                )) {
                    Button("Cancel", role: .cancel) {
                        pendingVisibilityChange = nil
                    }
                    Button("Change") {
                        applyPendingVisibilityChange()
                    }
                } message: {
                    Text(visibilityChangeMessage(for: pendingVisibilityChange))
                }
                .onAppear {
                    profile.handle = profile.handle
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
                    initialFullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                    initialHandle = profile.handle
                    employersText = profile.employers.joined(separator: ", ")
                    guard let initialTarget else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(initialTarget, anchor: .center)
                        }
                        focusedField = initialTarget
                    }
                }
            }
            .background(PassportTheme.background)
            .navigationTitle("Edit Profile")
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
                        let trimmedHeadline = profile.headline.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedHeadline.count > 100 {
                            validationMessage = "Headline must be 100 characters or fewer."
                            return
                        }
                        let trimmedFullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedFullName != initialFullName,
                           let fullNameLastChangedAt = profile.fullNameLastChangedAt,
                           let nextAllowedDate = Calendar.current.date(byAdding: .day, value: 7, to: fullNameLastChangedAt),
                           nextAllowedDate > .now {
                            validationMessage = "Full name can only be changed once every 7 days."
                            return
                        }
                        let trimmedHandle = SharedFormatters.profileHandle(profile.handle)
                        if !trimmedHandle.isEmpty && trimmedHandle.count < 3 {
                            validationMessage = "Handle must be at least 3 characters."
                            return
                        }
                        if trimmedHandle.count > 30 {
                            validationMessage = "Handle must be 30 characters or fewer."
                            return
                        }
                        if trimmedHandle != initialHandle,
                           let handleLastChangedAt = profile.handleLastChangedAt,
                           let nextAllowedDate = Calendar.current.date(byAdding: .day, value: 30, to: handleLastChangedAt),
                           nextAllowedDate > .now {
                            validationMessage = "Handle can only be changed once every 30 days."
                            return
                        }
                        if !profile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let normalized = profile.linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            let candidateURL = normalized.lowercased().hasPrefix("http://") || normalized.lowercased().hasPrefix("https://") ? normalized : "https://\(normalized)"
                            guard let url = URL(string: candidateURL),
                                  let host = url.host?.lowercased(),
                                  host.contains("linkedin.com") else {
                                validationMessage = "LinkedIn must be a valid linkedin.com URL."
                                return
                            }
                            profile.linkedInURL = candidateURL
                        }
                        profile.fullName = trimmedFullName
                        profile.handle = trimmedHandle
                        profile.instagramUsername = normalizedSocialUsername(profile.instagramUsername)
                        profile.tiktokUsername = normalizedSocialUsername(profile.tiktokUsername)

                        profile.employers = employersText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
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
                .focused($focusedField, equals: .fullName)

            Text("Can be changed once every 7 days.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.fullName)
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Handle")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                if let handleLastChangedAt = profile.handleLastChangedAt {
                    Text(handleCooldownText(from: handleLastChangedAt))
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                }
            }

            TextField("mayachen", text: Binding(
                get: { profile.handle },
                set: { profile.handle = SharedFormatters.profileHandle($0) }
            ))
                .textFieldStyle(PassportTextFieldStyle())
                .focused($focusedField, equals: .handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Lowercase letters, numbers, and underscores only. Can be changed once every 30 days.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.handle)
    }

    private var headlineField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Headline")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(profile.headline.count)/100")
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            TextField("Your short professional bio", text: Binding(
                get: { profile.headline },
                set: { profile.headline = String($0.prefix(100)) }
            ), axis: .vertical)
            .textFieldStyle(PassportTextFieldStyle())
            .lineLimit(3...5)
            .focused($focusedField, equals: .headline)

            Text("100 characters max.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.headline)
    }

    private var dreamRoleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dream role")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(profile.dreamRole.count)/50")
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            TextField("Dream role", text: Binding(
                get: { profile.dreamRole },
                set: { profile.dreamRole = String($0.prefix(50)) }
            ))
            .textFieldStyle(PassportTextFieldStyle())
            .focused($focusedField, equals: .dreamRole)

            Text("50 characters max.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.dreamRole)
    }

    private var schoolField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("School")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(profile.school.count)/200")
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            TextField("School", text: Binding(
                get: { profile.school },
                set: { profile.school = String($0.prefix(200)) }
            ))
            .textFieldStyle(PassportTextFieldStyle())
            .focused($focusedField, equals: .school)

            Text("200 characters max.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.school)
    }

    private var employersField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Previous employers")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(employersText.count)/400")
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            TextField("Figma, Notion, Stripe", text: Binding(
                get: { employersText },
                set: { employersText = String($0.prefix(400)) }
            ), axis: .vertical)
            .textFieldStyle(PassportTextFieldStyle())
            .lineLimit(3...6)
            .focused($focusedField, equals: .employers)

            Text("400 characters max.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.employers)
    }

    private var compensationRangeField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compensation")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Menu {
                Button("Not set") {
                    profile.desiredCompensationRange = ""
                }
                ForEach(CandidateCompensationRange.allCases) { option in
                    Button(option.rawValue) {
                        profile.desiredCompensationRange = option.rawValue
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(profile.desiredCompensationRange.isEmpty ? "Not set" : profile.desiredCompensationRange)
                        .foregroundStyle(PassportTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PassportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(PassportTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.compensation)
    }

    private var linkedInField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LinkedIn URL")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField("https://linkedin.com/in/you", text: $profile.linkedInURL)
                .textFieldStyle(PassportTextFieldStyle())
                .focused($focusedField, equals: .linkedIn)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Text("Must be a valid LinkedIn URL.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(CandidateProfileEditTarget.linkedIn)
    }

    private func socialUsernameField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        target: CandidateProfileEditTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            HStack(spacing: 10) {
                Text("@")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PassportTheme.textSecondary)
                TextField(placeholder, text: Binding(
                    get: { text.wrappedValue },
                    set: { text.wrappedValue = normalizedSocialUsername($0) }
                ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: target)
            }
            .textFieldStyle(PassportTextFieldStyle())

            Text("Enter just the username. scout22 links it automatically.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(target)
    }

    private func handleCooldownText(from date: Date) -> String {
        let nextAllowedDate = Calendar.current.date(byAdding: .day, value: 30, to: date) ?? date
        if nextAllowedDate <= .now {
            return "Available now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Again \(formatter.localizedString(for: nextAllowedDate, relativeTo: .now))"
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


    private func normalizedSocialUsername(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^A-Za-z0-9._]", with: "", options: .regularExpression)
    }

    private func applyPendingVisibilityChange() {
        guard let pendingVisibilityChange else { return }
        profile.visibility = pendingVisibilityChange
        self.pendingVisibilityChange = nil
    }

    private func visibilityChangeMessage(for visibility: CandidateVisibility?) -> String {
        switch visibility {
        case .discoverableToHiringEmployers:
            return "Changing to Public will make your profile discoverable by all hiring employers."
        case .appliedRolesOnly, .private:
            return "Changing to Private will make your profile viewable only to employers you’ve applied to."
        case nil:
            return ""
        }
    }

    private func profileField(
        title: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        placeholder: String? = nil,
        target: CandidateProfileEditTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField(placeholder ?? title, text: text, axis: axis)
                .textFieldStyle(PassportTextFieldStyle())
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .focused($focusedField, equals: target)
        }
        .padding(18)
        .jobTokCard(cornerRadius: 22)
        .id(target)
    }
}

private struct MinimalApplicationRow: View {
    let application: JobApplicationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PassportTheme.card)
                    .frame(width: 54, height: 54)
                Text(String(application.companyName.prefix(1)).uppercased())
                    .font(.headline.weight(.black))
                    .foregroundStyle(PassportTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(application.jobTitle)
                            .font(.headline)
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text(application.companyName)
                            .font(.subheadline)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    Spacer()
                    Text(application.status.capitalized)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PassportTheme.card)
                        .foregroundStyle(PassportTheme.textPrimary)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    if let location = application.jobLocation, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    Label(application.emailDeliveryStatus.capitalized, systemImage: "paperplane")
                }
                .font(.caption)
                .foregroundStyle(PassportTheme.textSecondary)

                Text(formattedAppliedDate(application.appliedAt))
                    .font(.caption)
                    .foregroundStyle(PassportTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func formattedAppliedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Applied \(formatter.localizedString(for: date, relativeTo: .now))"
    }
}

private struct SavedJobCard: View {
    let job: JobPostingRecord
    let isApplied: Bool
    let isSaved: Bool
    let onApply: () -> Void
    let onToggleSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(job.companyName)
                        .font(.subheadline)
                        .foregroundStyle(PassportTheme.textSecondary)
                }

                Spacer()

                Button(action: onToggleSaved) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSaved ? .black : PassportTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(isSaved ? PassportTheme.accent : PassportTheme.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let location = job.location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            HStack(spacing: 8) {
                if let compensationText {
                    Text(compensationText)
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
            }

            Text(job.description)
                .font(.subheadline)
                .foregroundStyle(PassportTheme.textPrimary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Text(isApplied ? "Applied" : "Not applied yet")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PassportTheme.card)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .clipShape(Capsule())

                Spacer()

                if !isApplied {
                    Button("Apply") {
                        onApply()
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .jobTokCard(cornerRadius: 24)
    }

    private var compensationText: String? { job.compensationSummary }

}

private struct PreviewURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ProfileChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let isComplete: Bool
    let kind: CandidateProfileChecklistKind
}

private enum CandidateProfileTab: String, CaseIterable, Identifiable {
    case video
    case about
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:
            return "Video"
        case .about:
            return "About"
        case .saved:
            return "Saved"
        }
    }
}

private enum CandidateProfileChecklistKind {
    case profilePhoto
    case resume
    case pitchVideo
    case linkedIn
    case professionalSocial
}

private enum CandidateProfileEditTarget: Hashable {
    case fullName
    case handle
    case headline
    case school
    case employers
    case dreamRole
    case compensation
    case linkedIn
    case instagram
    case tiktok
    case jobFunction
}

private enum CandidateCompensationRange: String, CaseIterable, Identifiable {
    case under50k = "Under $50k"
    case between50kAnd75k = "$50k-$75k"
    case between75kAnd100k = "$75k-$100k"
    case between100kAnd125k = "$100k-$125k"
    case between125kAnd150k = "$125k-$150k"
    case between150kAnd175k = "$150k-$175k"
    case between175kAnd200k = "$175k-$200k"
    case over200k = "$200k+"

    var id: String { rawValue }
}

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private enum JobPayFilter: String, CaseIterable, Identifiable {
    case all
    case under100k
    case between100kAnd150k
    case over150k
    case undisclosed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Pay"
        case .under100k: return "< $100k"
        case .between100kAnd150k: return "$100k-$150k"
        case .over150k: return "$150k+"
        case .undisclosed: return "Undisclosed"
        }
    }

    func matches(_ job: JobPostingRecord) -> Bool {
        let minimum = job.compensationMinAnnual
        let maximum = job.compensationMaxAnnual

        switch self {
        case .all:
            return true
        case .undisclosed:
            return minimum == nil && maximum == nil
        case .under100k:
            guard let upper = maximum ?? minimum else { return false }
            return upper < 100_000
        case .between100kAnd150k:
            let lower = minimum ?? maximum ?? 0
            let upper = maximum ?? minimum ?? 0
            return lower <= 150_000 && upper >= 100_000
        case .over150k:
            let lower = minimum ?? maximum ?? 0
            let upper = maximum ?? minimum ?? 0
            return upper >= 150_000 || lower >= 150_000
        }
    }
}

// MARK: - Easy Apply

private struct EasyApplyConfirmationSheet: View {
    let job: JobPostingRecord
    let resumeFileName: String
    let onConfirm: () -> Void
    let onAdvanced: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Easy Apply")
                    .font(.title3.bold())
                Text("\(job.title) · \(job.companyName)")
                    .font(.subheadline)
                    .foregroundStyle(PassportTheme.textSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PassportTheme.accent)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume attached")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PassportTheme.textPrimary)
                    Text(resumeFileName)
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .background(PassportTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: onConfirm) {
                Text("Submit Application")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PassportTheme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button(action: onAdvanced) {
                Text("Add pitch video or social link")
                    .font(.subheadline)
                    .foregroundStyle(PassportTheme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(PassportTheme.background)
    }
}

private struct EasyApplySuccessBanner: View {
    let jobTitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Application submitted!")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(jobTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

// MARK: - Heart burst (double-tap save)

/// TikTok-style heart pop: scales up with a spring, drifts up, fades out.
/// `trigger` changing replays the animation.
struct HeartBurstView: View {
    let trigger: Int
    @State private var animate = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 96))
            .foregroundStyle(PassportTheme.accent)
            .shadow(color: .black.opacity(0.35), radius: 12)
            .scaleEffect(animate ? 1.0 : 0.3)
            .opacity(animate ? 0 : 1)
            .offset(y: animate ? -60 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: animate)
            .onAppear { replay() }
            .onChange(of: trigger) { _, _ in replay() }
    }

    private func replay() {
        animate = false
        DispatchQueue.main.async { animate = true }
    }
}
