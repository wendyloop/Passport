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
    let candidateVideos: [CandidateVideoRecord]
    let onSetPrimaryVideo: (String) -> Void
    let onDeleteVideo: (String) -> Void
    let onUpdateVideoCaption: (String, String?) -> Void
    let session: AuthSession?
    // F10: job id arriving from a share deep link; the feed scrolls to it.
    let sharedJobID: String?
    let onConsumeSharedJob: () -> Void
    let onSaveProfile: (CandidateProfileDraft) -> Void
    let onUploadAvatar: (Data) -> Void
    let onUploadResume: (URL) -> Void
    let onUploadVideo: (URL, Double, String?) -> Void
    let onRequestResumePreview: () async throws -> URL?
    let onApply: (JobApplicationDraft) -> Void
    let onToggleSavedJob: (String) -> Void
    let onRefresh: () -> Void
    let onShowNotifications: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void
    // Server-side filter refetch: fires whenever a filter pill changes so the
    // store can re-query the whole catalog, not just the fetched window.
    let onFiltersChanged: (FeedFilters) -> Void

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
    @State private var selectedLocationFilter: LocationFilter = .all
    @State private var selectedJobFunctionRawValue = "all"
    @State private var selectedPayFilter: JobPayFilter = .all
    @State private var selectedExperienceFilter: ExperienceFilter = .all
    @State private var selectedWorkModeFilter: WorkModeFilter = .all
    @State private var selectedCompanySizeFilter: CompanySizeFilter = .all
    @State private var founderReachableOnly = false
    @State private var selectedProfileTab: CandidateProfileTab = .video
    @State private var showingStrengthDetail = false
    @State private var profilePlayerItem: ProfileVideoPlayerItem?
    @State private var pendingVideoPost: PendingVideoPost?
    // Saved/applied jobs open as real feed cards (carousel + apply/pitch),
    // rendered as an in-hierarchy overlay — NOT a modal — so the apply and
    // founder sheets can still present above it.
    @State private var savedFeedJobs: [JobPostingRecord] = []
    @State private var savedFeedStartJob: JobPostingRecord?
    @State private var savedFeedCurrentJobID: String?
    @State private var captionEditingVideo: CandidateVideoRecord?
    @State private var captionDraft = ""
    @State private var profileEditorTarget: CandidateProfileEditTarget?
    @State private var pendingVisibilityChange: CandidateVisibility?

    init(
        profile: CandidateProfileDraft,
        jobs: [JobPostingRecord],
        savedJobs: [JobPostingRecord],
        savedJobIDs: Set<String>,
        applications: [JobApplicationRecord],
        candidateVideos: [CandidateVideoRecord] = [],
        onSetPrimaryVideo: @escaping (String) -> Void = { _ in },
        onDeleteVideo: @escaping (String) -> Void = { _ in },
        onUpdateVideoCaption: @escaping (String, String?) -> Void = { _, _ in },
        session: AuthSession? = nil,
        sharedJobID: String? = nil,
        onConsumeSharedJob: @escaping () -> Void = {},
        onSaveProfile: @escaping (CandidateProfileDraft) -> Void,
        onUploadAvatar: @escaping (Data) -> Void,
        onUploadResume: @escaping (URL) -> Void,
        onUploadVideo: @escaping (URL, Double, String?) -> Void,
        onRequestResumePreview: @escaping () async throws -> URL?,
        onApply: @escaping (JobApplicationDraft) -> Void,
        onToggleSavedJob: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onShowNotifications: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void,
        onFiltersChanged: @escaping (FeedFilters) -> Void = { _ in }
    ) {
        self.profile = profile
        self.jobs = jobs
        self.savedJobs = savedJobs
        self.savedJobIDs = savedJobIDs
        self.applications = applications
        self.candidateVideos = candidateVideos
        self.onSetPrimaryVideo = onSetPrimaryVideo
        self.onDeleteVideo = onDeleteVideo
        self.onUpdateVideoCaption = onUpdateVideoCaption
        self.session = session
        self.sharedJobID = sharedJobID
        self.onConsumeSharedJob = onConsumeSharedJob
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
        self.onFiltersChanged = onFiltersChanged
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

    /// Snapshot of the server-backed filters; changing any of them refetches
    /// the feed with these applied in the PostgREST query.
    private var currentFilters: FeedFilters {
        FeedFilters(
            location: selectedLocationFilter,
            experience: selectedExperienceFilter,
            workMode: selectedWorkModeFilter,
            pay: selectedPayFilter,
            jobFunction: selectedJobFunction,
            founderReachable: founderReachableOnly,
            companySize: selectedCompanySizeFilter
        )
    }

    private var filteredJobs: [JobPostingRecord] {
        jobs.filter { job in
            let locationMatches = selectedLocationFilter.matches(job)

            let functionMatches: Bool = {
                guard let selectedJobFunction else { return true }
                return job.jobFunction == selectedJobFunction
            }()

            let payMatches = selectedPayFilter.matches(job)
            let experienceMatches = selectedExperienceFilter.matches(job)
            let workModeMatches = selectedWorkModeFilter.matches(job)
            let stageMatches = !founderReachableOnly || job.founderPitchAllowed
            let sizeMatches = selectedCompanySizeFilter.matches(job)
            // Carousel-backed rows (ATS + board) need at least one slide this
            // build can draw. No carousel yet (generate-carousel hasn't run) or
            // a carousel made entirely of unknown slide types → nothing to
            // render, so hide it.
            let renderable = !job.sourceKind.rendersCarousel || (job.carousel?.hasRenderableSlides ?? false)
            return renderable && !brokenJobIDs.contains(job.id) && locationMatches && functionMatches && payMatches
                && experienceMatches && workModeMatches && stageMatches && sizeMatches
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

            if savedFeedStartJob != nil {
                savedFeedViewer
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .tint(PassportTheme.accent)
        .onChange(of: currentFilters) { _, filters in
            onFiltersChanged(filters)
        }
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
                videos: candidateVideos,
                onRecordPitch: { showingVideoStudio = true },
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
                    videos: candidateVideos,
                    onRecordPitch: { showingVideoStudio = true },
                    onAddResume: { showingResumeImporter = true },
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
        .onChange(of: sharedJobID) { _, incoming in
            guard let incoming else { return }
            selectedTab = .jobs
            if jobs.contains(where: { $0.id == incoming }) {
                currentJobID = incoming
            }
            onConsumeSharedJob()
        }
        .fullScreenCover(item: $pendingVideoPost) { pending in
            VideoPostView(
                composed: pending.composed,
                onPost: { caption in
                    pendingVideoPost = nil
                    onUploadVideo(pending.composed.url, pending.composed.duration, caption)
                },
                onCancel: { pendingVideoPost = nil }
            )
        }
        .fullScreenCover(isPresented: $showingVideoStudio) {
            Scout22VideoStudio(
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
                                    safeAreaBottom: proxy.safeAreaInsets.bottom,
                                    activeJobID: currentJobID
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
        safeAreaBottom: CGFloat,
        activeJobID: String?
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
                    isActive: activeJobID == job.id,
                    onApply: { handleApplyTap(for: job) },
                    // FIRST-100-USERS: hide/show the pitch CTA via
                    // FounderPitchUI.isEnabled (SharedFormatters.swift).
                    onEmailFounder: (FounderPitchUI.isEnabled && job.founderPitchAllowed)
                        ? { handleEmailFounderTap(for: job) } : nil,
                    onSave: { onToggleSavedJob(job.id) },
                    isSaved: savedJobIDs.contains(job.id)
                )
            } else {
                JobFeedCard(
                    job: job,
                    safeAreaBottom: safeAreaBottom,
                    alreadyApplied: appliedJobIDs.contains(job.id),
                    isSaved: savedJobIDs.contains(job.id),
                    isActive: activeJobID == job.id,
                    onToggleSaved: { onToggleSavedJob(job.id) },
                    onApply: { handleApplyTap(for: job) },
                    // FIRST-100-USERS: hide/show the pitch CTA via
                    // FounderPitchUI.isEnabled (SharedFormatters.swift).
                    onEmailFounder: (FounderPitchUI.isEnabled && job.founderPitchAllowed)
                        ? { handleEmailFounderTap(for: job) } : nil,
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
        } else if workingProfile.resumeStoragePath != nil && workingProfile.introVideoURL != nil {
            // Unified pitch: one-tap only when both required pieces exist.
            easyApplyConfirmation = job
        } else {
            applicationDraft = makeApplicationDraft(for: job)
            applyingJob = job
        }
    }

    private func handleEmailFounderTap(for job: JobPostingRecord) {
        founderEmailJob = job
    }

    // Applied tiles open the job's feed card when the job is still
    // resolvable (feed window or the saved-jobs id-fetch); snapshot-only
    // applications just don't navigate.
    private func resolvedJob(for application: JobApplicationRecord) -> JobPostingRecord? {
        jobs.first { $0.id == application.jobID }
            ?? savedJobs.first { $0.id == application.jobID }
    }

    private func openApplicationJob(_ application: JobApplicationRecord) {
        guard let job = resolvedJob(for: application) else { return }
        openFeedViewer(jobs: [job], startAt: job)
    }

    // Saved/applied tiles open the real feed experience: same cards, same
    // apply/pitch buttons, paged vertically — just scoped to the tapped set.
    //
    // The tapped card becomes page ZERO, with the rest of the set wrapped
    // behind it (IG-saved style). Feeding the whole array and asking
    // scrollPosition(id:) to restore a mid-list page misaligns under
    // .paging — the initial restore lands off by the safe-area inset, so
    // every card after it bled the next card's top into the bottom of the
    // screen (page one was fine; deeper start pages weren't). Starting at
    // offset zero sidesteps the restore entirely.
    private func openFeedViewer(jobs: [JobPostingRecord], startAt job: JobPostingRecord) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            savedFeedJobs = Array(jobs[idx...]) + Array(jobs[..<idx])
        } else {
            savedFeedJobs = jobs
        }
        savedFeedCurrentJobID = job.id
        withAnimation(.easeInOut(duration: 0.22)) {
            savedFeedStartJob = job
        }
    }

    private var savedFeedViewer: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let pageHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(savedFeedJobs) { job in
                            feedCard(
                                job: job,
                                pageWidth: pageWidth,
                                pageHeight: pageHeight,
                                safeAreaBottom: proxy.safeAreaInsets.bottom,
                                activeJobID: savedFeedCurrentJobID
                            )
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $savedFeedCurrentJobID)
                .frame(width: pageWidth, height: pageHeight)
                .offset(y: -proxy.safeAreaInsets.top)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        savedFeedStartJob = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.top, 8)
            }
        }
    }

    private var applicationsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader(
                        title: "Applications",
                        subtitle: "Every pitch you’ve sent, at a glance."
                    )

                    if applications.isEmpty {
                        InfoCard(
                            title: "No applications yet",
                            details: "Apply to a job from the feed and it will appear here."
                        )
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(applications) { application in
                                ApplicationTile(
                                    application: application,
                                    job: resolvedJob(for: application),
                                    onOpen: { openApplicationJob(application) }
                                )
                            }
                        }
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
                .alert("Profile strength", isPresented: $showingStrengthDetail) {
                    Button("Edit profile") { isEditingProfile = true }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(strengthDetailMessage)
                }
                .fullScreenCover(item: $profilePlayerItem) { item in
                    // TikTok-style: full screen, tap to pause, X to close.
                    ZStack(alignment: .topLeading) {
                        Color.black.ignoresSafeArea()
                        RemoteVideoSurface(
                            urlString: item.url,
                            isActive: true,
                            videoGravity: .resizeAspect,
                            autoPlay: true,
                            allowsTapToTogglePlayback: true,
                            showsPlayOverlayWhenPaused: true
                        )
                        .ignoresSafeArea()
                        Button {
                            profilePlayerItem = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 14)
                        .padding(.top, 8)
                    }
                    .overlay(alignment: .bottom) {
                        // Visible video actions — primary selection shouldn't
                        // hide behind a long-press.
                        if let video = item.video {
                            HStack(spacing: 10) {
                                if video.isPrimary {
                                    Label("Primary video", systemImage: "star.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(Capsule().fill(PassportTheme.accent))
                                        .foregroundStyle(.black)
                                } else {
                                    Button {
                                        profilePlayerItem = nil
                                        onSetPrimaryVideo(video.id)
                                    } label: {
                                        Label("Set as primary", systemImage: "star")
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Capsule().fill(Color.white.opacity(0.16)))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    profilePlayerItem = nil
                                    captionDraft = video.caption ?? ""
                                    captionEditingVideo = video
                                } label: {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(Color.white.opacity(0.16)))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    profilePlayerItem = nil
                                    onDeleteVideo(video.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.red)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(Color.white.opacity(0.16)))
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .alert("Caption", isPresented: Binding(
                    get: { captionEditingVideo != nil },
                    set: { if !$0 { captionEditingVideo = nil } }
                )) {
                    TextField("Say what this video shows", text: $captionDraft)
                    Button("Save") {
                        if let video = captionEditingVideo {
                            let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            onUpdateVideoCaption(video.id, trimmed.isEmpty ? nil : String(trimmed.prefix(150)))
                        }
                        captionEditingVideo = nil
                    }
                    Button("Cancel", role: .cancel) { captionEditingVideo = nil }
                } message: {
                    Text("Shown on the video tile, like a TikTok caption.")
                }

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
                        ForEach(LocationFilter.allCases) { option in
                            Button(option.menuTitle) {
                                selectedLocationFilter = option
                            }
                        }
                    } label: {
                        filterPill(title: selectedLocationFilter.title)
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

                    Menu {
                        ForEach(ExperienceFilter.allCases) { option in
                            Button(option.title) {
                                selectedExperienceFilter = option
                            }
                        }
                    } label: {
                        filterPill(title: selectedExperienceFilter.title)
                    }

                    Menu {
                        ForEach(WorkModeFilter.allCases) { option in
                            Button(option.title) {
                                selectedWorkModeFilter = option
                            }
                        }
                    } label: {
                        filterPill(title: selectedWorkModeFilter.title)
                    }

                    Menu {
                        ForEach(CompanySizeFilter.allCases) { option in
                            Button(option.menuTitle) {
                                selectedCompanySizeFilter = option
                            }
                        }
                    } label: {
                        filterPill(title: selectedCompanySizeFilter.title)
                    }

                    // F4: founder-reachable — jobs where the pitch button is
                    // actually available (startup stage + contact on file).
                    Button {
                        founderReachableOnly.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text("🚀 Founder-reachable")
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(founderReachableOnly ? .black : PassportTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(founderReachableOnly ? PassportTheme.accent : PassportTheme.card)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            HeaderAction(symbol: "bell.fill", action: onShowNotifications)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .scout22ChromeCapsule()
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

    // P redesign (mock v4): identity only — no stat row, no link chips
    // (links live in the About tab). Strength ring replaces the checklist.
    private var candidateProfileHero: some View {
        VStack(spacing: 12) {
            // Mock v4 layout: avatar on the left, identity on the right —
            // less vertical space up top, more room for the content below.
            HStack(alignment: .center, spacing: 14) {
                profileAvatar
                    .overlay(alignment: .bottomLeading) {
                        profileStrengthBadge
                            .offset(x: -6, y: 4)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(workingProfile.fullName.isEmpty ? "Your Name" : workingProfile.fullName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PassportTheme.textPrimary)
                        .lineLimit(1)

                    Text(handleText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PassportTheme.textSecondary)

                    Text(bioText)
                        .font(.footnote)
                        .foregroundStyle(hasCustomBio ? PassportTheme.textPrimary : PassportTheme.textMuted)
                        .lineLimit(2)
                        .padding(.top, 1)

                    if !heroMetaText.isEmpty {
                        Text(heroMetaText)
                            .font(.caption)
                            .foregroundStyle(PassportTheme.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                isEditingProfile = true
            } label: {
                Text("Edit profile")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PassportTheme.border.opacity(0.65), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .scout22Card(cornerRadius: 24)
    }

    private var profileStrengthBadge: some View {
        Button {
            showingStrengthDetail = true
        } label: {
            Text("\(ProfileStrength.score(for: workingProfile))%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PassportTheme.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(PassportTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(PassportTheme.accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var strengthDetailMessage: String {
        let missing = ProfileStrength.missing(for: workingProfile)
        if missing.isEmpty {
            return "Complete — everything employers look for is here."
        }
        let items = missing.map { "\($0.label) (+\($0.points))" }.joined(separator: "\n")
        return "Still missing:\n\(items)"
    }

    private var heroMetaText: String {
        var parts: [String] = []
        let school = workingProfile.school.trimmingCharacters(in: .whitespacesAndNewlines)
        if !school.isEmpty { parts.append(school) }
        let dream = workingProfile.dreamRole.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dream.isEmpty { parts.append("open to \(dream)") }
        return parts.joined(separator: " · ")
    }

    private func normalizedOptionalURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
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
        }
    }

    // P redesign + M-C: full-bleed TikTok-style grid — 3 columns, 1pt
    // seams, escaping the screen's 20pt content padding. One tile per video
    // (long-press for primary/caption/delete) + a persistent "New video"
    // tile. Falls back to the intro mirror if the list hasn't loaded.
    private var profileVideoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if candidateVideos.isEmpty && workingProfile.introVideoURL == nil {
                // No videos yet: one big CTA instead of a lonely grid cell.
                Button {
                    showingVideoStudio = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text("Record your first pitch")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text("The first thing employers see — unlocks founder intros. Up to 3:00.")
                            .font(.caption)
                            .foregroundStyle(PassportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PassportTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Spacer()
                    Button {
                        showingVideoStudio = true
                    } label: {
                        Label("New video", systemImage: "plus")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(PassportTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                    if candidateVideos.isEmpty, let introURL = workingProfile.introVideoURL {
                        videoTile(urlString: introURL, caption: nil, isPrimary: true)
                    } else {
                        ForEach(candidateVideos) { video in
                            videoTile(urlString: video.videoURL, caption: video.caption, isPrimary: video.isPrimary, record: video)
                                .contextMenu {
                                    if !video.isPrimary {
                                        Button("Set as primary") { onSetPrimaryVideo(video.id) }
                                    }
                                    Button("Edit caption") {
                                        captionDraft = video.caption ?? ""
                                        captionEditingVideo = video
                                    }
                                    Button("Delete video", role: .destructive) { onDeleteVideo(video.id) }
                                }
                        }
                    }
                }
                .padding(.horizontal, -20)
            }
        }
    }

    private func videoTile(urlString: String, caption: String?, isPrimary: Bool, record: CandidateVideoRecord? = nil) -> some View {
        Button {
            profilePlayerItem = ProfileVideoPlayerItem(url: urlString, video: record)
        } label: {
            RemoteVideoSurface(
                urlString: urlString,
                isActive: true,
                videoGravity: .resizeAspectFill,
                autoPlay: false,
                allowsTapToTogglePlayback: false,
                showsPlayOverlayWhenPaused: false
            )
            // The embedded UIKit player view must never eat the tile tap.
            .allowsHitTesting(false)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topLeading) {
                if isPrimary {
                    Text("Primary")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PassportTheme.surface.opacity(0.94))
                        .foregroundStyle(PassportTheme.textPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // P redesign About tab: the profile builds itself from the parsed
    // resume; links close it out with per-role relevance hints.
    private var profileAboutTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            aboutResumeCard
            aboutExperienceSection
            aboutEducationSection
            aboutSkillsSection
            aboutLinksSection
            // visibilityModeCard intentionally omitted — candidate-only v0,
            // see the comment on the card below.
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
        .padding(.bottom, 8)
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

    // IG-saved-tab style: a grid of tiles, applied state flagged on the
    // tile, and tapping the bookmark unsaves in place (optimistic — the
    // tile disappears immediately).
    private var savedJobsTab: some View {
        Group {
            if savedJobs.isEmpty {
                InfoCard(
                    title: "No saved jobs yet",
                    details: "Save roles from the feed and they’ll show up here."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(savedJobs) { job in
                        SavedJobTile(
                            job: job,
                            isApplied: appliedJobIDs.contains(job.id),
                            onOpen: {
                                // Open the real feed card (carousel + apply /
                                // pitch buttons), scoped to the saved set.
                                openFeedViewer(jobs: savedJobs, startAt: job)
                            },
                            onUnsave: {
                                onToggleSavedJob(job.id)
                            }
                        )
                    }
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
            return "Add a short bio"
        }
        return parts.joined(separator: " ")
    }

    private var hasCustomBio: Bool {
        !workingProfile.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var aboutResumeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 24))
                .foregroundStyle(PassportTheme.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(workingProfile.resumeFileName ?? "Add your resume")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PassportTheme.textPrimary)
                    .lineLimit(1)
                if let imported = workingProfile.resumeImportedAt {
                    Text("Updated \(imported.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textMuted)
                } else {
                    Text("Powers your About section and founder pitches")
                        .font(.caption)
                        .foregroundStyle(PassportTheme.textMuted)
                }
            }

            Spacer(minLength: 8)

            if workingProfile.resumeStoragePath == nil {
                Button {
                    showingResumeImporter = true
                } label: {
                    Text("Add")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                resumeStatusPill

                Menu {
                    Button("View resume") {
                        Task {
                            do {
                                resumePreviewURL = try await onRequestResumePreview()
                            } catch {
                                importErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    Button("Update resume") {
                        showingResumeImporter = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PassportTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(PassportTheme.card)
                        .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .scout22Card(cornerRadius: 20)
    }

    @ViewBuilder
    private var resumeStatusPill: some View {
        switch workingProfile.resumeParseStatus {
        case "parsed":
            Text("Parsed")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(Capsule())
        case "failed", "pending_manual_review":
            Text("Needs review")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PassportTheme.card)
                .foregroundStyle(PassportTheme.textSecondary)
                .clipShape(Capsule())
        default:
            Text("Parsing…")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PassportTheme.card)
                .foregroundStyle(PassportTheme.textSecondary)
                .clipShape(Capsule())
        }
    }

    private var aboutExperienceSection: some View {
        let parsedJobs = (workingProfile.parsedResume?.employers ?? []).filter {
            trimmedOrNil($0.company) != nil || trimmedOrNil($0.title) != nil
        }
        return VStack(alignment: .leading, spacing: 10) {
            aboutSectionLabel(parsedJobs.isEmpty ? "Experience" : "Experience · auto-filled from your resume")

            if !parsedJobs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(parsedJobs.prefix(6).enumerated()), id: \.offset) { _, job in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(experienceTitleLine(job))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(PassportTheme.textPrimary)
                            if let detail = experienceDetailLine(job) {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(PassportTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(PassportTheme.border)
                        .frame(width: 2)
                }
            } else if !workingProfile.employers.isEmpty {
                Text(workingProfile.employers.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(PassportTheme.textSecondary)
            } else {
                Button {
                    showingResumeImporter = true
                } label: {
                    Text("Add your resume and this section fills itself in.")
                        .font(.footnote)
                        .foregroundStyle(PassportTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var aboutEducationSection: some View {
        let entries = (workingProfile.parsedResume?.education ?? []).filter {
            trimmedOrNil($0.school) != nil
        }
        let fallbackSchool = trimmedOrNil(workingProfile.school)
        if !entries.isEmpty || fallbackSchool != nil {
            VStack(alignment: .leading, spacing: 10) {
                aboutSectionLabel("Education")
                if !entries.isEmpty {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.school ?? "")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(PassportTheme.textPrimary)
                            if let detail = educationDetailLine(entry) {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(PassportTheme.textSecondary)
                            }
                        }
                    }
                } else if let fallbackSchool {
                    Text(fallbackSchool)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var aboutSkillsSection: some View {
        let skills = (workingProfile.parsedResume?.skills ?? [])
            .compactMap(trimmedOrNil)
            .prefix(12)
        if !skills.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                aboutSectionLabel("Skills")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                        Text(skill)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().stroke(PassportTheme.border.opacity(0.8), lineWidth: 1)
                            )
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                }
            }
        }
    }

    // Links close out About with per-role relevance hints: different
    // reviewers check different links, and the fine print says so (the same
    // note repeats in onboarding once M-D ships).
    private var aboutLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            aboutSectionLabel("Links")

            VStack(spacing: 0) {
                profileLinkRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    value: trimmedOrNil(workingProfile.githubURL),
                    placeholder: "Add GitHub",
                    relevance: "engineering",
                    url: normalizedOptionalURLString(workingProfile.githubURL).flatMap { URL(string: $0) },
                    target: .github
                )
                Divider()
                profileLinkRow(
                    icon: "person.crop.rectangle",
                    value: trimmedOrNil(workingProfile.linkedInURL),
                    placeholder: "Add LinkedIn",
                    relevance: "all roles",
                    url: linkedInURL,
                    target: .linkedIn
                )
                Divider()
                profileLinkRow(
                    icon: "camera",
                    value: trimmedOrNil(workingProfile.instagramUsername).map { "@\(normalizedUsernameDisplay($0))" },
                    placeholder: "Add Instagram",
                    relevance: "marketing",
                    url: instagramURL,
                    target: .instagram
                )
                Divider()
                profileLinkRow(
                    icon: "music.note",
                    value: trimmedOrNil(workingProfile.tiktokUsername).map { "@\(normalizedUsernameDisplay($0))" },
                    placeholder: "Add TikTok",
                    relevance: "marketing",
                    url: tiktokURL,
                    target: .tiktok
                )
                Divider()
                profileLinkRow(
                    icon: "paintpalette",
                    value: trimmedOrNil(workingProfile.portfolioURL),
                    placeholder: "Add portfolio",
                    relevance: "design",
                    url: normalizedOptionalURLString(workingProfile.portfolioURL).flatMap { URL(string: $0) },
                    target: .portfolio
                )
            }
            .scout22Card(cornerRadius: 20)

            Text("Different reviewers check different links — marketing looks at Instagram and TikTok, engineering at GitHub, design at your portfolio.")
                .font(.caption2)
                .foregroundStyle(PassportTheme.textMuted)
        }
    }

    @ViewBuilder
    private func profileLinkRow(
        icon: String,
        value: String?,
        placeholder: String,
        relevance: String,
        url: URL?,
        target: CandidateProfileEditTarget
    ) -> some View {
        let label = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(PassportTheme.textSecondary)
                .frame(width: 20)
            Text(value.map(displayLinkText) ?? placeholder)
                .font(.footnote)
                .foregroundStyle(value == nil ? PassportTheme.textMuted : PassportTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(relevance)
                .font(.caption2)
                .foregroundStyle(PassportTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())

        if let url, value != nil {
            Link(destination: url) { label }
        } else {
            Button {
                openProfileEditor(target: target)
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private func aboutSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(PassportTheme.textMuted)
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func displayLinkText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }

    private func experienceTitleLine(_ job: ParsedResumeDetails.Employer) -> String {
        [trimmedOrNil(job.title), trimmedOrNil(job.company)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func experienceDetailLine(_ job: ParsedResumeDetails.Employer) -> String? {
        let start = trimmedOrNil(job.startDate)
        let end = job.isCurrent == true ? "now" : trimmedOrNil(job.endDate)
        switch (start, end) {
        case let (start?, end?): return "\(start) – \(end)"
        case let (start?, nil): return "\(start) –"
        case let (nil, end?): return "– \(end)"
        case (nil, nil): return nil
        }
    }

    private func educationDetailLine(_ entry: ParsedResumeDetails.Education) -> String? {
        let degreeField = [trimmedOrNil(entry.degree), trimmedOrNil(entry.fieldOfStudy)]
            .compactMap { $0 }
            .joined(separator: " ")
        let parts = [degreeField.isEmpty ? nil : degreeField, trimmedOrNil(entry.graduationYear)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // HIDDEN for candidate-only v0 (deliberately kept compiled, not rendered):
    // there is no employer or admin view yet and candidates can never read
    // each other's content (enforced by the discovery_visibility RLS policies,
    // which remain fully intact server-side). The toggle therefore has no
    // user-facing effect today, and everyone stays on the server default —
    // public/discoverable (migration 20260715120000) — because employer-side
    // discovery needs a full candidate pool and available videos are the
    // bottleneck to launching the employer side. When the employer view ships:
    // re-add this card to profileAboutTab, restore the "Mode" stat cell, and
    // reintroduce the discovery_visibility write in
    // CandidateService.upsertJobSeekerProfile.
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
        .scout22Card(cornerRadius: 28)
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
                .frame(width: 84, height: 84)

            if let avatarURL = workingProfile.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarInitials
                }
                .frame(width: 78, height: 78)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PassportTheme.textPrimary)
                    .padding(6)
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
            .frame(width: 78, height: 78)
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

    private func normalizedUsernameDisplay(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
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

    private func acceptComposedVideo(_ composedVideo: Scout22ComposedVideo) {
        workingProfile.introVideoFileName = composedVideo.fileName
        workingProfile.introVideoDuration = composedVideo.duration
        // TikTok flow: the studio hands off to a post page (caption +
        // preview) instead of uploading immediately. Small delay so the
        // studio's cover finishes dismissing before the next one presents.
        let pending = PendingVideoPost(composed: composedVideo)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            pendingVideoPost = pending
        }
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
                                Label("Pitch the founder", systemImage: "paperplane.fill")
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
                        if let shareURL = ShareConfig.shareURL(forJobID: job.id) {
                            FeedShareButton(url: shareURL)
                        }
                    }
                    .frame(width: 56)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, safeAreaBottom + FeedLayout.cardBottomClearance)
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
    var videos: [CandidateVideoRecord] = []
    var onRecordPitch: () -> Void = {}
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func videoMenuTitle(_ video: CandidateVideoRecord) -> String {
        let caption = video.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (caption?.isEmpty == false ? caption! : "Untitled video")
        return video.isPrimary ? "\(base) · Primary" : base
    }

    private var selectedVideoTitle: String {
        guard let selected = videos.first(where: { $0.videoURL == draft.pitchVideoURL }) else {
            return "Primary video"
        }
        return videoMenuTitle(selected)
    }

    private var canApply: Bool {
        draft.resumeFilePath != nil
            && draft.pitchVideoURL != nil
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pitch video")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PassportTheme.textPrimary)
                        Text(draft.pitchVideoURL == nil
                            ? "Required — every application is a video pitch. Record one and it rides along with your resume."
                            : "Required — sent alongside your resume.")
                            .font(.footnote)
                            .foregroundStyle(PassportTheme.textSecondary)
                    }

                    if draft.pitchVideoURL == nil {
                        Button {
                            dismiss()
                            onRecordPitch()
                        } label: {
                            Label("Record your pitch", systemImage: "video.badge.plus")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .buttonStyle(.plain)
                    } else if videos.count > 1 {
                        // M-C: pick which video rides along.
                        Menu {
                            ForEach(videos) { video in
                                Button(videoMenuTitle(video)) {
                                    draft.pitchVideoURL = video.videoURL
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "video.fill")
                                    .font(.caption)
                                Text(selectedVideoTitle)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(PassportTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PassportTheme.surface)
                            .clipShape(Capsule())
                        }
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
    @State private var editableExperience: [EditableExperienceEntry] = []
    @State private var editableEducation: [EditableEducationEntry] = []
    @State private var skillsText = ""
    @State private var validationMessage: String?
    @State private var initialFullName = ""
    @State private var initialHandle = ""
    @State private var pendingVisibilityChange: CandidateVisibility?
    @FocusState private var focusedField: CandidateProfileEditTarget?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // LinkedIn-style grouped sections: related fields
                        // share one card under a small section header.
                        editorSection("Intro") {
                            fullNameField
                            editorDivider
                            handleField
                            editorDivider
                            headlineField
                        }

                        editorSection("Background") {
                            schoolField
                            editorDivider
                            employersField
                            editorDivider
                            dreamRoleField
                            editorDivider
                            jobFunctionField
                        }

                        editorSection("Experience") {
                            experienceEditor
                        }

                        editorSection("Education & skills") {
                            educationEditor
                            editorDivider
                            skillsEditor
                        }

                        editorSection("Preferences") {
                            compensationRangeField
                        }

                        editorSection("Links") {
                            roleSpotlightHint
                            linkFields
                        }

                        // The editor's Visibility toggle is hidden for
                        // candidate-only v0 (same rationale as
                        // visibilityModeCard: no employer view yet, everyone
                        // stays on the public server default, and the client
                        // no longer writes discovery_visibility at all).
                        // Restore this section when the employer view ships.

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
                    let parsed = profile.parsedResume
                    editableExperience = (parsed?.employers ?? []).map {
                        EditableExperienceEntry(
                            title: $0.title ?? "",
                            company: $0.company ?? "",
                            start: $0.startDate ?? "",
                            end: $0.endDate ?? "",
                            isCurrent: $0.isCurrent ?? false
                        )
                    }
                    editableEducation = (parsed?.education ?? []).map {
                        EditableEducationEntry(
                            school: $0.school ?? "",
                            degree: $0.degree ?? "",
                            field: $0.fieldOfStudy ?? "",
                            year: $0.graduationYear ?? ""
                        )
                    }
                    skillsText = (parsed?.skills ?? []).joined(separator: ", ")
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
                        profile.parsedResume = serializedParsedResume()
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(PassportTheme.accent)
                }
            }
        }
    }

    private var experienceEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shown on your profile's About tab — auto-filled from your resume, yours to correct.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)

            ForEach($editableExperience) { $entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Position")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PassportTheme.textMuted)
                        Spacer()
                        Button {
                            editableExperience.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("Title (SWE Intern)", text: $entry.title)
                        .textFieldStyle(PassportTextFieldStyle())
                    TextField("Company (Stripe)", text: $entry.company)
                        .textFieldStyle(PassportTextFieldStyle())
                    HStack(spacing: 8) {
                        TextField("Start (2025-06)", text: $entry.start)
                            .textFieldStyle(PassportTextFieldStyle())
                        TextField("End", text: $entry.end)
                            .textFieldStyle(PassportTextFieldStyle())
                            .disabled(entry.isCurrent)
                            .opacity(entry.isCurrent ? 0.4 : 1)
                    }
                    Toggle(isOn: $entry.isCurrent) {
                        Text("I currently work here")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PassportTheme.textSecondary)
                    }
                    .tint(PassportTheme.accent)
                }
                .padding(12)
                .background(PassportTheme.card.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                editableExperience.append(EditableExperienceEntry())
            } label: {
                Label("Add position", systemImage: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(PassportTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var educationEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach($editableEducation) { $entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Education")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PassportTheme.textMuted)
                        Spacer()
                        Button {
                            editableEducation.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("School (UC Berkeley)", text: $entry.school)
                        .textFieldStyle(PassportTextFieldStyle())
                    HStack(spacing: 8) {
                        TextField("Degree (BS)", text: $entry.degree)
                            .textFieldStyle(PassportTextFieldStyle())
                        TextField("Field (CS)", text: $entry.field)
                            .textFieldStyle(PassportTextFieldStyle())
                        TextField("Year", text: $entry.year)
                            .textFieldStyle(PassportTextFieldStyle())
                            .frame(width: 76)
                    }
                }
                .padding(12)
                .background(PassportTheme.card.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                editableEducation.append(EditableEducationEntry())
            } label: {
                Label("Add education", systemImage: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(PassportTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var skillsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skills")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)
            TextField("Swift, Go, Figma…", text: $skillsText, axis: .vertical)
                .textFieldStyle(PassportTextFieldStyle())
                .lineLimit(2...4)
            Text("Comma-separated. Shown as chips on your profile.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
    }

    private func serializedParsedResume() -> ParsedResumeDetails? {
        let jobs = editableExperience.compactMap { entry -> ParsedResumeDetails.Employer? in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let company = entry.company.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !company.isEmpty else { return nil }
            let start = entry.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = entry.end.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedResumeDetails.Employer(
                company: company.isEmpty ? nil : company,
                title: title.isEmpty ? nil : title,
                startDate: start.isEmpty ? nil : start,
                endDate: entry.isCurrent || end.isEmpty ? nil : end,
                isCurrent: entry.isCurrent
            )
        }
        let education = editableEducation.compactMap { entry -> ParsedResumeDetails.Education? in
            let school = entry.school.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !school.isEmpty else { return nil }
            let degree = entry.degree.trimmingCharacters(in: .whitespacesAndNewlines)
            let field = entry.field.trimmingCharacters(in: .whitespacesAndNewlines)
            let year = entry.year.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedResumeDetails.Education(
                school: school,
                degree: degree.isEmpty ? nil : degree,
                fieldOfStudy: field.isEmpty ? nil : field,
                graduationYear: year.isEmpty ? nil : year
            )
        }
        let skills = skillsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if jobs.isEmpty && education.isEmpty && skills.isEmpty && profile.parsedResume == nil {
            return nil
        }
        return ParsedResumeDetails(
            currentTitle: profile.parsedResume?.currentTitle,
            employers: jobs,
            education: education,
            skills: skills
        )
    }

    private var editorDivider: some View {
        Divider().overlay(PassportTheme.border.opacity(0.4))
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PassportTheme.textMuted)
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(18)
            .scout22Card(cornerRadius: 22)
        }
    }

    private var jobFunctionField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job function")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Menu {
                ForEach(JobFunctionOption.allCases) { option in
                    Button(option.title) { profile.jobFunction = option }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(profile.jobFunction.title)
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

            Text("Orders your links and powers the feed's role filters.")
                .font(.footnote)
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .id(CandidateProfileEditTarget.jobFunction)
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
        .id(CandidateProfileEditTarget.linkedIn)
    }

    // Links ordered by what matters for this person's role: engineers lead
    // with GitHub, designers with a portfolio, marketing/social folks with
    // TikTok + Instagram. Everyone keeps LinkedIn.
    @ViewBuilder
    private var linkFields: some View {
        switch profile.jobFunction {
        case .engineering, .science:
            githubField
            linkedInField
            portfolioField
            socialUsernameField(title: "Instagram", text: $profile.instagramUsername, placeholder: "yourhandle", target: .instagram)
            socialUsernameField(title: "TikTok", text: $profile.tiktokUsername, placeholder: "yourhandle", target: .tiktok)
        case .design:
            portfolioField
            linkedInField
            githubField
            socialUsernameField(title: "Instagram", text: $profile.instagramUsername, placeholder: "yourhandle", target: .instagram)
            socialUsernameField(title: "TikTok", text: $profile.tiktokUsername, placeholder: "yourhandle", target: .tiktok)
        case .marketing:
            socialUsernameField(title: "TikTok", text: $profile.tiktokUsername, placeholder: "yourhandle", target: .tiktok)
            socialUsernameField(title: "Instagram", text: $profile.instagramUsername, placeholder: "yourhandle", target: .instagram)
            linkedInField
            portfolioField
            githubField
        default:
            linkedInField
            socialUsernameField(title: "Instagram", text: $profile.instagramUsername, placeholder: "yourhandle", target: .instagram)
            socialUsernameField(title: "TikTok", text: $profile.tiktokUsername, placeholder: "yourhandle", target: .tiktok)
            portfolioField
            githubField
        }
    }

    private var roleSpotlightHint: some View {
        let hint: String
        switch profile.jobFunction {
        case .engineering, .science:
            hint = "Your GitHub is your portfolio — founders click it before your resume."
        case .design:
            hint = "Your portfolio does the talking — make it the first thing they see."
        case .marketing:
            hint = "Your TikTok and Instagram ARE your track record — link them."
        default:
            hint = "A strong LinkedIn is your anchor — add anything else that shows your work."
        }
        return HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(PassportTheme.accent)
            Text(hint)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PassportTheme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PassportTheme.accentSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var githubField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GitHub")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField("https://github.com/you", text: $profile.githubURL)
                .textFieldStyle(PassportTextFieldStyle())
                .focused($focusedField, equals: .github)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .id(CandidateProfileEditTarget.github)
    }

    private var portfolioField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portfolio")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            TextField("https://yourfolio.com", text: $profile.portfolioURL)
                .textFieldStyle(PassportTextFieldStyle())
                .focused($focusedField, equals: .portfolio)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .id(CandidateProfileEditTarget.portfolio)
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
        .id(target)
    }
}

// TikTok-style applied-job tile: same visual family as SavedJobTile, with
// the application status as the headline signal.
private struct ApplicationTile: View {
    let application: JobApplicationRecord
    var job: JobPostingRecord? = nil
    let onOpen: () -> Void

    private var style: CarouselStyle {
        // Falls back to the denormalised company name when the job row hasn't
        // loaded — same value displayCompanyName yields for a company-less row,
        // so the tile keeps matching the feed in the common case.
        CarouselStyle.resolve(
            companyKey: job?.carouselCompanyKey ?? application.companyName,
            themeID: job?.carousel?.themeId ?? "slate-gradient"
        )
    }

    private var statusLabel: String {
        if application.emailDeliveryStatus == "failed" { return "RETRYING" }
        // A pitch that hasn't been followed by a real application reads as its
        // own thing — it went straight to a founder, not into an ATS.
        if application.isFounderPitch { return "PITCHED" }
        switch application.status {
        case "submitted": return "SENT"
        case "reviewing": return "REVIEWING"
        case "contacted": return "CONTACTED"
        case "rejected": return "CLOSED"
        case "hired": return "HIRED"
        default: return application.status.uppercased()
        }
    }

    private var statusColor: Color {
        if application.emailDeliveryStatus == "failed" { return .orange }
        if application.isFounderPitch { return Color(red: 0.65, green: 0.80, blue: 1.00) }
        switch application.status {
        case "contacted", "hired": return Color(red: 0.45, green: 0.85, blue: 0.55)
        case "rejected": return Color.white.opacity(0.35)
        default: return Color(red: 0.96, green: 0.88, blue: 0.60)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .top) {
                if let job {
                    JobTileBackground(job: job, style: style)
                } else {
                    fallbackSummary
                }

                HStack(alignment: .top) {
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(statusColor))
                    Spacer()
                }
                .padding(8)
            }
            .aspectRatio(0.8, contentMode: .fit)
            .overlay(alignment: .bottom) {
                JobTileFooter(title: application.jobTitle, caption: footerCaption)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footerCaption: String {
        var parts = [application.companyName]
        if let comp = job?.compensationSummary { parts.append(comp) }
        if let mode = job?.workMode, !mode.isEmpty { parts.append(mode.capitalized) }
        let verb = application.isFounderPitch ? "pitched" : "applied"
        parts.append("\(verb) \(SharedFormatters.relativeAge(of: application.appliedAt))")
        // An application that started as a pitch keeps both facts visible.
        if !application.isFounderPitch, application.didPitchFounder {
            parts.append("founder pitched")
        }
        return parts.joined(separator: " · ")
    }

    private var fallbackSummary: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CompanyMonogram(
                name: application.companyName,
                background: style.theme.accent,
                foreground: style.theme.onAccent,
                size: 44
            )
        }
    }
}

private struct SavedJobTile: View {
    let job: JobPostingRecord
    let isApplied: Bool
    let onOpen: () -> Void
    let onUnsave: () -> Void

    private var style: CarouselStyle {
        CarouselStyle.resolve(companyKey: job.carouselCompanyKey, themeID: job.carousel?.themeId ?? "slate-gradient")
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .top) {
                JobTileBackground(job: job, style: style)

                HStack(alignment: .top) {
                    if isApplied {
                        Text("APPLIED")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(red: 0.45, green: 0.85, blue: 0.55)))
                    }
                    Spacer()
                    Button(action: onUnsave) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(red: 0.96, green: 0.88, blue: 0.60)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
            .aspectRatio(0.8, contentMode: .fit)
            .overlay(alignment: .bottom) {
                JobTileFooter(title: job.title, caption: footerCaption)
            }
            // Fixed dark ground (not the adaptive card color): the tile's
            // white text and accent identity must hold in light mode too.
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footerCaption: String {
        var parts = [job.displayCompanyName]
        if let comp = job.compensationSummary { parts.append(comp) }
        if let mode = job.workMode, !mode.isEmpty { parts.append(mode.capitalized) }
        parts.append(SharedFormatters.relativeAge(of: job.createdAt))
        return parts.joined(separator: " · ")
    }
}

// Shared tile ground: the job's REAL cover card when a carousel exists,
// monogram summary otherwise (video jobs, not-yet-generated carousels).
private struct JobTileBackground: View {
    let job: JobPostingRecord
    let style: CarouselStyle

    var body: some View {
        if let carousel = job.carousel, JobCardPreview.canPreview(job: job, carousel: carousel) {
            JobCardPreview(job: job, carousel: carousel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Text lives in the tile footer; this is just a themed ground.
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                CompanyMonogram(
                    name: job.displayCompanyName,
                    background: style.theme.accent,
                    foreground: style.theme.onAccent,
                    size: 44
                )
            }
        }
    }
}

// Stats footer shared by Saved/Applications tiles: title bold, facts as
// fine-print captions (company · comp · work mode · age), sitting directly
// on the artwork like the original tiles — no band, just a soft shadow
// for legibility.
private struct JobTileFooter: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EditableExperienceEntry: Identifiable {
    let id = UUID()
    var title = ""
    var company = ""
    var start = ""
    var end = ""
    var isCurrent = false
}

private struct EditableEducationEntry: Identifiable {
    let id = UUID()
    var school = ""
    var degree = ""
    var field = ""
    var year = ""
}

private struct ProfileVideoPlayerItem: Identifiable {
    let id = UUID()
    let url: String
    var video: CandidateVideoRecord? = nil
}

private struct PendingVideoPost: Identifiable {
    let id = UUID()
    let composed: Scout22ComposedVideo
}

// TikTok-style post page: looping preview beside a caption field, one big
// Post button. The caption tells reviewers what this video is about ("my
// intro", "walkthrough of my hackathon project"…).
private struct VideoPostView: View {
    let composed: Scout22ComposedVideo
    let onPost: (String?) -> Void
    let onCancel: () -> Void

    @State private var caption = ""
    @FocusState private var captionFocused: Bool

    private static let maxCaptionChars = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PassportTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(PassportTheme.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("New video")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "Describe your video — \"my 60-sec intro\", \"walkthrough of my hackathon project\"…",
                        text: $caption,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .focused($captionFocused)
                    .foregroundStyle(PassportTheme.textPrimary)
                    .onChange(of: caption) { _, newValue in
                        if newValue.count > Self.maxCaptionChars {
                            caption = String(newValue.prefix(Self.maxCaptionChars))
                        }
                    }

                    Text("\(caption.count)/\(Self.maxCaptionChars)")
                        .font(.caption2)
                        .foregroundStyle(PassportTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                RemoteVideoSurface(
                    urlString: composed.url.absoluteString,
                    isActive: true,
                    videoGravity: .resizeAspectFill,
                    autoPlay: true,
                    allowsTapToTogglePlayback: false,
                    showsPlayOverlayWhenPaused: false,
                    isMuted: true
                )
                .allowsHitTesting(false)
                .frame(width: 104, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(16)
            .scout22Card(cornerRadius: 20)

            Spacer()

            Button {
                let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                onPost(trimmed.isEmpty ? nil : trimmed)
            } label: {
                Label("Post", systemImage: "paperplane.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(PassportTheme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PassportTheme.background.ignoresSafeArea())
        .onAppear { captionFocused = true }
    }
}

private struct PreviewURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private enum CandidateProfileTab: String, CaseIterable, Identifiable {
    case video
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:
            return "Videos"
        case .about:
            return "About"
        }
    }
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
    case github
    case portfolio
    
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

// Internal (not private): FeedFilters carries it into SupabaseService for
// the server-side arm of filtering.
enum JobPayFilter: String, CaseIterable, Identifiable {
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

// MARK: - F2 feed filters (experience + work mode)

enum ExperienceFilter: String, CaseIterable, Identifiable {
    case all
    case earlyCareer
    case mid
    case senior
    case leadership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Experience"
        case .earlyCareer: return "Early career"
        case .mid: return "Mid-level"
        case .senior: return "Senior"
        case .leadership: return "Leadership"
        }
    }

    func matches(_ job: JobPostingRecord) -> Bool {
        switch self {
        case .all: return true
        case .earlyCareer: return job.experienceLevel == "intern" || job.experienceLevel == "entry"
        case .mid: return job.experienceLevel == "mid"
        case .senior: return job.experienceLevel == "senior" || job.experienceLevel == "staff"
        case .leadership: return job.experienceLevel == "exec"
        }
    }
}

enum WorkModeFilter: String, CaseIterable, Identifiable {
    case all
    case remote
    case hybrid
    case onsite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Work mode"
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        case .onsite: return "In office"
        }
    }

    func matches(_ job: JobPostingRecord) -> Bool {
        self == .all || job.workMode == rawValue
    }
}

// Location presets over free-text `jobs.location` (87–100% populated, but
// unnormalized — "New York, NY" / "NYC" / "Brooklyn"). Metro presets match
// substrings; Remote also accepts work_mode. A per-value exact-match menu
// (the previous design) was useless against free text.
enum LocationFilter: String, CaseIterable, Identifiable {
    case all
    case remote
    case bayArea
    case nyc
    case losAngeles
    case seattle
    case austin
    case boston
    case chicago

    var id: String { rawValue }

    /// Pill label when selected.
    var title: String {
        switch self {
        case .all: return "Location"
        case .remote: return "Remote"
        case .bayArea: return "SF Bay Area"
        case .nyc: return "New York"
        case .losAngeles: return "Los Angeles"
        case .seattle: return "Seattle"
        case .austin: return "Austin"
        case .boston: return "Boston"
        case .chicago: return "Chicago"
        }
    }

    var menuTitle: String {
        self == .all ? "All locations" : title
    }

    /// Lowercased substrings that identify the metro in free-text locations.
    var patterns: [String] {
        switch self {
        case .all, .remote: return []
        case .bayArea:
            return ["san francisco", "bay area", "palo alto", "mountain view", "menlo park",
                    "oakland", "berkeley", "san jose", "sunnyvale", "redwood city", "cupertino"]
        case .nyc: return ["new york", "nyc", "brooklyn"]
        case .losAngeles: return ["los angeles", "santa monica", "culver city"]
        case .seattle: return ["seattle", "bellevue", "redmond"]
        case .austin: return ["austin"]
        case .boston: return ["boston", "cambridge, ma"]
        case .chicago: return ["chicago"]
        }
    }

    func matches(_ job: JobPostingRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .remote:
            if job.workMode == "remote" { return true }
            return job.location?.lowercased().contains("remote") ?? false
        default:
            guard let location = job.location?.lowercased() else { return false }
            return patterns.contains { location.contains($0) }
        }
    }
}

// Company headcount buckets, backed by companies.size_bucket — a generated
// column derived from the crawlers' headcount field where it's trustworthy
// plus stage labels/funding stage (migration 20260730150000). Jobs at
// unknown-size companies (~38% of the catalog) only appear under "All".
enum CompanySizeFilter: String, CaseIterable, Identifiable {
    case all
    case under10 = "under_10"
    case from10To100 = "10_100"
    case from100To1000 = "100_1000"
    case over1000 = "1000_plus"

    var id: String { rawValue }

    /// The companies.size_bucket value to filter on; nil = no filtering.
    var bucketValue: String? {
        self == .all ? nil : rawValue
    }

    var title: String {
        switch self {
        case .all: return "Company Size"
        case .under10: return "Under 10 people"
        case .from10To100: return "10–100 people"
        case .from100To1000: return "100–1,000 people"
        case .over1000: return "1,000+ people"
        }
    }

    var menuTitle: String {
        self == .all ? "Any size" : title
    }

    func matches(_ job: JobPostingRecord) -> Bool {
        guard let bucketValue else { return true }
        return job.company?.sizeBucket == bucketValue
    }
}

// The server-backed filter set. The feed fetch window is capped (200+200
// rows of a 33k catalog), so filtering client-side alone silently missed
// almost everything; these translate into PostgREST params so the narrowing
// happens over the whole catalog. Server conditions may be a SUPERSET of
// the exact semantics (pay banding with null bounds is awkward in
// PostgREST); `filteredJobs` re-applies the exact `matches()` pass on the
// result, so what renders is always correct.
struct FeedFilters: Equatable {
    var location: LocationFilter = .all
    var experience: ExperienceFilter = .all
    var workMode: WorkModeFilter = .all
    var pay: JobPayFilter = .all
    // Server-side too: the fetch window is 200+200 of a 33k catalog, so
    // client-only role/founder filtering starved results (e.g. Product ×
    // founder-reachable = 180 real jobs, ~1 in a typical window).
    var jobFunction: JobFunctionOption? = nil
    var founderReachable: Bool = false
    // Applied on the embedded company row (companies.size_bucket), so like
    // founderReachable it's wired up in fetchJobs, not postgrestParams.
    var companySize: CompanySizeFilter = .all

    /// PostgREST conditions, ANDed with the feed query. Multiple `or=`
    /// params are separate top-level conditions (PostgREST ANDs them).
    var postgrestParams: [(String, String)] {
        var params: [(String, String)] = []

        if let jobFunction {
            params.append(("job_function", "eq.\(jobFunction.rawValue)"))
        }

        switch experience {
        case .all: break
        case .earlyCareer: params.append(("experience_level", "in.(intern,entry)"))
        case .mid: params.append(("experience_level", "eq.mid"))
        case .senior: params.append(("experience_level", "in.(senior,staff)"))
        case .leadership: params.append(("experience_level", "eq.exec"))
        }

        if workMode != .all {
            params.append(("work_mode", "eq.\(workMode.rawValue)"))
        }

        switch pay {
        case .all: break
        case .undisclosed:
            params.append(("compensation_min_annual", "is.null"))
            params.append(("compensation_max_annual", "is.null"))
        case .under100k:
            params.append(("or", "(compensation_min_annual.lt.100000,compensation_max_annual.lt.100000)"))
        case .between100kAnd150k:
            // Superset: any listed salary; exact banding client-side.
            params.append(("or", "(compensation_min_annual.not.is.null,compensation_max_annual.not.is.null)"))
        case .over150k:
            params.append(("or", "(compensation_min_annual.gte.150000,compensation_max_annual.gte.150000)"))
        }

        switch location {
        case .all:
            break
        case .remote:
            params.append(("or", "(work_mode.eq.remote,location.ilike.*remote*)"))
        default:
            // Patterns are double-quoted: PostgREST's or=() splits clauses on
            // commas, so the unquoted "cambridge, ma" pattern parsed as two
            // broken conditions and 400'd the ENTIRE feed refetch — picking
            // Boston killed the query and left the feed stale. Quoted values
            // are comma- and space-safe (REST-verified against the hosted
            // project for every metro).
            let clauses = location.patterns.map { "location.ilike.\"*\($0)*\"" }.joined(separator: ",")
            params.append(("or", "(\(clauses))"))
        }

        return params
    }
}
