import Foundation

// TODO(deferred): CandidateStore split. This store still holds all three
// roles' ~20 @Published props, which feed NativeRootView's per-role closures.
// Splitting candidate state into its own ObservableObject means rewiring those
// closures, so do it alongside the employer/admin view refactor. Effort:
// medium. See docs/DEFERRED_WORK.md.
@MainActor
final class AppSessionStore: ObservableObject {
    enum Phase {
        case launching
        case signedOut
        case onboarding
        case signedIn
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: AppProfileRecord?
    @Published private(set) var jobSeekerProfile: JobSeekerProfileRecord?
    @Published private(set) var employerProfile: EmployerProfileRecord?
    @Published private(set) var jobSeekerEmployers: [JobSeekerEmployerRecord] = []
    @Published private(set) var latestResume: ResumeUploadRecord?
    @Published private(set) var notifications: [NotificationRecord] = []
    @Published private(set) var jobFeed: [JobPostingRecord] = []
    @Published private(set) var savedJobRecords: [SavedJobRecord] = []
    @Published private(set) var candidateApplications: [JobApplicationRecord] = []
    @Published private(set) var employerJobs: [JobPostingRecord] = []
    @Published private(set) var employerApplications: [JobApplicationRecord] = []
    @Published private(set) var discoverableCandidates: [DiscoverableCandidateRecord] = []
    @Published private(set) var employerOutreachMessages: [CandidateOutreachRecord] = []
    @Published private(set) var adminJobs: [JobPostingRecord] = []
    @Published private(set) var employerDirectoryItems: [EmployerDirectoryItem] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    // F10: job id from a share deep link (jobtok://job/{id}) waiting for the
    // feed to scroll to it. Consumed by JobSeekerHomeView.
    @Published var pendingSharedJobID: String?

    private let service = SupabaseService.shared
    private var auth: AuthService { service.auth }
    private var candidate: CandidateService { service.candidate }
    private let defaults = UserDefaults.standard
    private let sessionKey = SharedConstants.sessionDefaultsKey
    private let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupID)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        Task { await bootstrap() }
    }

    var role: UserRole? {
        profile?.role
    }

    var currentEmail: String? {
        session?.user.email
    }

    var notificationsUnreadCount: Int {
        notifications.filter { $0.readAt == nil }.count
    }

    var candidateDraft: CandidateProfileDraft {
        CandidateProfileDraft(
            fullName: profile?.fullName ?? "",
            fullNameLastChangedAt: profile?.fullNameLastChangedAt,
            headline: profile?.headline ?? "",
            handle: profile?.handle ?? "",
            handleLastChangedAt: profile?.handleLastChangedAt,
            avatarURL: profile?.avatarURL,
            school: jobSeekerProfile?.schoolName ?? latestResume?.parsedSchoolName ?? "",
            employers: jobSeekerEmployers.map(\.employerName),
            jobFunction: jobSeekerProfile?.jobFunction ?? .engineering,
            dreamRole: jobSeekerProfile?.dreamRole ?? "",
            desiredCompensationRange: jobSeekerProfile?.desiredCompensationRange ?? mappedCompensationRange(from: jobSeekerProfile?.desiredCompensationAnnual),
            linkedInURL: jobSeekerProfile?.linkedInURL ?? "",
            instagramUsername: jobSeekerProfile?.instagramUsername ?? "",
            tiktokUsername: jobSeekerProfile?.tiktokUsername ?? "",
            githubURL: jobSeekerProfile?.githubURL ?? "",
            portfolioURL: jobSeekerProfile?.portfolioURL ?? "",
            visibility: jobSeekerProfile?.discoveryVisibility ?? .appliedRolesOnly,
            resumeFileName: latestResume?.filePath.split(separator: "/").last.map(String.init),
            resumeStoragePath: latestResume?.filePath,
            resumeImportedAt: latestResume?.createdAt,
            introVideoFileName: jobSeekerProfile?.introVideoURL?.split(separator: "/").last.map(String.init),
            introVideoDuration: nil,
            introVideoURL: jobSeekerProfile?.introVideoURL
        )
    }

    var employerDraft: EmployerProfileDraft {
        EmployerProfileDraft(
            fullName: profile?.fullName ?? "",
            fullNameLastChangedAt: profile?.fullNameLastChangedAt,
            headline: profile?.headline ?? "",
            companyName: employerProfile?.companyName ?? "",
            companyDomain: employerProfile?.companyDomain ?? "",
            positionTitle: employerProfile?.positionTitle ?? ""
        )
    }

    var latestOutreachByCandidateID: [String: CandidateOutreachRecord] {
        employerOutreachMessages.reduce(into: [:]) { partialResult, message in
            if partialResult[message.candidateProfileID] == nil {
                partialResult[message.candidateProfileID] = message
            }
        }
    }

    var savedJobIDs: Set<String> {
        Set(savedJobRecords.map(\.jobID))
    }

    var savedJobs: [JobPostingRecord] {
        let jobLookup = Dictionary(uniqueKeysWithValues: jobFeed.map { ($0.id, $0) })
        return savedJobRecords.compactMap { jobLookup[$0.jobID] }
    }

    func bootstrap() async {
        if let savedSession = loadPersistedSession() {
            session = savedSession
            do {
                self.session = try await auth.ensureValidSession(savedSession)
                try persistSessionIfNeeded()
                try await loadCurrentUserState()
            } catch {
                clearSession()
                phase = .signedOut
                errorMessage = error.localizedDescription
            }
        } else {
            phase = .signedOut
        }
    }

    func signUp(email: String, password: String) async {
        await runBusyTask { [self] in
            let session = try await auth.signUp(email: email, password: password)
            self.session = session
            try persistSessionIfNeeded()
            try await loadCurrentUserState()
        }
    }

    func signIn(email: String, password: String) async {
        await runBusyTask { [self] in
            let session: AuthSession
            do {
                session = try await auth.signIn(email: email, password: password)
            } catch {
                AppLog.session.error("Sign-in auth failed: \(String(describing: error))")
                throw error
            }
            self.session = session
            try persistSessionIfNeeded()
            do {
                try await loadCurrentUserState()
            } catch {
                AppLog.session.error("Post-sign-in state load failed: \(String(describing: error))")
                throw error
            }
        }
    }

    func signOut() async {
        if let session {
            await auth.signOut(session: session)
        }
        clearSession()
        phase = .signedOut
    }

    func deleteAccount() async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            try await service.deleteAccount(session: session)
            clearSession()
            phase = .signedOut
        }
    }

    func handleAuthRedirect(url: URL) async {
        await runBusyTask { [self] in
            let session = try await auth.session(fromAuthRedirectURL: url)
            self.session = session
            try persistSessionIfNeeded()
            try await loadCurrentUserState()
        }
    }

    func oauthAuthorizationURL(provider: SocialAuthProvider, redirectTo: URL) throws -> URL {
        try auth.oauthAuthorizationURL(provider: provider, redirectTo: redirectTo)
    }

    func completeOnboarding(
        fullName: String,
        headline: String,
        schoolName: String,
        employers: [String],
        jobFunction: JobFunctionOption,
        dreamRole: String,
        companyName: String,
        companyDomain: String,
        positionTitle: String,
        resumeURL: URL?,
        introVideoURL: URL?,
        introVideoDuration: Double?
    ) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let resolvedRole = profile?.role ?? .jobSeeker

            try await service.upsertProfile(
                userID: userID,
                email: currentEmail,
                fullName: fullName,
                handle: profile?.handle,
                avatarURL: profile?.avatarURL,
                includeAvatarURL: true,
                headline: headline,
                onboardingComplete: true,
                session: session
            )

            switch resolvedRole {
            case .jobSeeker:
                var uploadedVideoPublicURL: String? = self.jobSeekerProfile?.introVideoURL

                if let introVideoURL {
                    let uploadURL = try await VideoProcessing.prepareVideoForUpload(introVideoURL)
                    let videoData = try Data(contentsOf: uploadURL)
                    let fileName = uploadURL.lastPathComponent
                    let result = try await service.uploadFile(
                        bucket: "videos",
                        path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                        data: videoData,
                        contentType: mimeType(for: uploadURL) ?? "video/mp4",
                        session: session
                    )
                    uploadedVideoPublicURL = result.publicURL
                    try await candidate.insertCandidateVideo(
                        userID: userID,
                        publicURL: result.publicURL,
                        durationSeconds: introVideoDuration.map { Int($0.rounded()) },
                        session: session
                    )
                }

                try await candidate.upsertJobSeekerProfile(
                    userID: userID,
                    schoolName: schoolName,
                    jobFunction: jobFunction,
                    dreamRole: dreamRole,
                    desiredCompensationAnnual: nil,
                    desiredCompensationRange: candidateDraft.desiredCompensationRange.nonEmptyValue,
                    linkedInURL: normalizedOptionalURL(candidateDraft.linkedInURL),
                    instagramUsername: normalizedUsername(candidateDraft.instagramUsername),
                    tiktokUsername: normalizedUsername(candidateDraft.tiktokUsername),
                    introVideoURL: uploadedVideoPublicURL,
                    visibility: .appliedRolesOnly,
                    githubURL: normalizedOptionalURL(candidateDraft.githubURL),
                    portfolioURL: normalizedOptionalURL(candidateDraft.portfolioURL),
                    session: session
                )
                try await candidate.replaceJobSeekerEmployers(userID: userID, employers: employers, session: session)

                if let resumeURL {
                    try await uploadResumeFile(userID: userID, fileURL: resumeURL, session: session)
                }
            case .employer:
                try await service.upsertEmployerProfile(
                    userID: userID,
                    companyName: companyName,
                    companyDomain: companyDomain,
                    positionTitle: positionTitle,
                    session: session
                )
            case .admin:
                break
            }

            try await loadCurrentUserState()
        }
    }

    func saveCandidateProfile(_ draft: CandidateProfileDraft) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()

            try await service.upsertProfile(
                userID: userID,
                email: currentEmail,
                fullName: draft.fullName,
                handle: normalizedHandle(draft.handle),
                avatarURL: profile?.avatarURL,
                includeAvatarURL: true,
                headline: draft.headline,
                onboardingComplete: true,
                session: session
            )
            try await candidate.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                dreamRole: draft.dreamRole,
                desiredCompensationAnnual: nil,
                desiredCompensationRange: draft.desiredCompensationRange.nonEmptyValue,
                linkedInURL: normalizedOptionalURL(draft.linkedInURL),
                instagramUsername: normalizedUsername(draft.instagramUsername),
                tiktokUsername: normalizedUsername(draft.tiktokUsername),
                introVideoURL: draft.introVideoURL,
                visibility: draft.visibility,
                githubURL: normalizedOptionalURL(draft.githubURL),
                portfolioURL: normalizedOptionalURL(draft.portfolioURL),
                session: session
            )
            try await candidate.replaceJobSeekerEmployers(userID: userID, employers: draft.employers, session: session)

            // Phase 2: when candidate discovery is turned on, visibility changes should
            // immediately influence employer browse queries rather than only applied-role access.

            try await loadCurrentUserState()
        }
    }

    func saveEmployerProfile(_ draft: EmployerProfileDraft) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()

            try await service.upsertProfile(
                userID: userID,
                email: currentEmail,
                fullName: draft.fullName,
                handle: profile?.handle,
                avatarURL: profile?.avatarURL,
                includeAvatarURL: true,
                headline: draft.headline,
                onboardingComplete: true,
                session: session
            )
            try await service.upsertEmployerProfile(
                userID: userID,
                companyName: draft.companyName,
                companyDomain: draft.companyDomain,
                positionTitle: draft.positionTitle,
                session: session
            )

            try await loadCurrentUserState()
        }
    }

    func uploadCandidateVideo(fileURL: URL, duration: Double) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let uploadURL = try await VideoProcessing.prepareVideoForUpload(fileURL)
            let fileName = uploadURL.lastPathComponent
            let videoData = try Data(contentsOf: uploadURL)

            let upload = try await service.uploadFile(
                bucket: "videos",
                path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                data: videoData,
                contentType: mimeType(for: uploadURL) ?? "video/mp4",
                session: session
            )
            try await candidate.insertCandidateVideo(
                userID: userID,
                publicURL: upload.publicURL,
                durationSeconds: Int(duration.rounded()),
                session: session
            )
            let draft = candidateDraft
            try await candidate.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                dreamRole: draft.dreamRole,
                desiredCompensationAnnual: nil,
                desiredCompensationRange: draft.desiredCompensationRange.nonEmptyValue,
                linkedInURL: normalizedOptionalURL(draft.linkedInURL),
                instagramUsername: normalizedUsername(draft.instagramUsername),
                tiktokUsername: normalizedUsername(draft.tiktokUsername),
                introVideoURL: upload.publicURL,
                visibility: draft.visibility,
                githubURL: normalizedOptionalURL(draft.githubURL),
                portfolioURL: normalizedOptionalURL(draft.portfolioURL),
                session: session
            )
            try await loadCurrentUserState()
        }
    }

    // P2: employer moves an application through the pipeline / edits notes.
    func updateApplication(applicationID: String, status: String? = nil, internalNotes: String? = nil) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            try await service.updateApplication(
                applicationID: applicationID,
                status: status,
                internalNotes: internalNotes,
                session: session
            )
            try await refreshEmployerData()
        }
    }

    // P1: short-lived signed resume URL for an application the employer owns.
    func resumeURL(applicationID: String) async throws -> URL {
        let session = try await requireSession()
        return try await service.resumeDownloadURL(applicationID: applicationID, session: session)
    }

    func toggleSavedJob(jobID: String) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()

            if savedJobIDs.contains(jobID) {
                try await candidate.unsaveJob(userID: userID, jobID: jobID, session: session)
            } else {
                try await candidate.saveJob(userID: userID, jobID: jobID, session: session)
            }

            try await refreshJobSeekerData()
        }
    }

    func uploadCandidateAvatar(imageData: Data) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let upload = try await service.uploadFile(
                bucket: "avatars",
                path: "\(userID)/avatar-\(Int(Date().timeIntervalSince1970)).jpg",
                data: imageData,
                contentType: "image/jpeg",
                session: session
            )

            try await service.upsertProfile(
                userID: userID,
                email: currentEmail,
                fullName: candidateDraft.fullName,
                handle: normalizedHandle(candidateDraft.handle),
                avatarURL: upload.publicURL,
                includeAvatarURL: true,
                headline: candidateDraft.headline,
                onboardingComplete: true,
                session: session
            )

            try await loadCurrentUserState()
        }
    }

    func uploadResume(fileURL: URL) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            try await uploadResumeFile(userID: userID, fileURL: fileURL, session: session)
            try await loadCurrentUserState()
        }
    }

    func requestResumePreviewURL() async throws -> URL? {
        let session = try await requireSession()
        guard let filePath = latestResume?.filePath else { return nil }
        return try await service.createSignedFileURL(
            bucket: "resumes",
            path: filePath,
            expiresIn: 60 * 30,
            session: session
        )
    }

    func applyToJob(_ draft: JobApplicationDraft) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            _ = try await candidate.applyToJob(draft: draft, session: session)
            try await loadCurrentUserState()
        }
    }

    func createJob(draft: JobPostingDraft, localVideoURL: URL?) async -> String? {
        let error = await runBusyTaskReturningError { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let resolvedVideoURL: String

            if let localVideoURL {
                let uploadURL = try await VideoProcessing.prepareVideoForUpload(localVideoURL)
                let fileName = uploadURL.lastPathComponent
                let videoData = try Data(contentsOf: uploadURL)

                let upload = try await service.uploadFile(
                    bucket: "job-videos",
                    path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                    data: videoData,
                    contentType: mimeType(for: uploadURL) ?? "video/mp4",
                    session: session
                )
                resolvedVideoURL = upload.publicURL
            } else if let importedVideoURL = draft.importedVideoURL.nonEmptyValue {
                resolvedVideoURL = importedVideoURL
            } else if let sourceURL = draft.sourceURL.nonEmptyValue {
                resolvedVideoURL = sourceURL
            } else {
                throw SupabaseServiceError.apiError("Select a video or import a social post link before publishing.")
            }

            // Link-import posts don't belong to a registered employer; video uploads must have one.
            let resolvedEmployerID: String?
            if localVideoURL != nil {
                guard !draft.employerProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SupabaseServiceError.apiError("Select an employer before publishing.")
                }
                resolvedEmployerID = draft.employerProfileID
            } else {
                resolvedEmployerID = draft.employerProfileID.nonEmptyValue
            }

            let trimmedCompanyName = draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let derivedCompanyName = trimmedCompanyName.isEmpty ? "Imported post" : trimmedCompanyName
            let derivedTitle = !trimmedTitle.isEmpty
                ? trimmedTitle
                : (draft.sourceCreatorName.nonEmptyValue.map { "\($0) hiring" } ?? "Imported post")
            let derivedDescription = !trimmedDescription.isEmpty
                ? trimmedDescription
                : (draft.sourceCaptionRaw.nonEmptyValue
                    ?? draft.sourceCaption.nonEmptyValue
                    ?? "Imported from \(draft.sourcePlatform?.title ?? "external source").")

            try await service.createJob(
                employerProfileID: resolvedEmployerID,
                title: derivedTitle,
                companyName: derivedCompanyName,
                location: draft.location,
                compensationMinAnnual: normalizedAnnualCompensation(from: draft.compensationMinAnnual),
                compensationMaxAnnual: normalizedAnnualCompensation(from: draft.compensationMaxAnnual),
                compensationMinHourly: normalizedHourlyCompensation(from: draft.compensationMinHourly),
                compensationMaxHourly: normalizedHourlyCompensation(from: draft.compensationMaxHourly),
                employmentType: draft.employmentType,
                jobFunction: draft.jobFunction,
                description: derivedDescription,
                applicationEmail: draft.applicationEmail,
                videoURL: resolvedVideoURL,
                sourceURL: draft.sourceURL,
                sourcePlatform: draft.sourcePlatform,
                sourceCreatorName: draft.sourceCreatorName.nonEmptyValue,
                sourceCreatorURL: draft.sourceCreatorURL.nonEmptyValue,
                sourceThumbnailURL: draft.sourceThumbnailURL.nonEmptyValue,
                sourceCaption: draft.sourceCaption.nonEmptyValue,
                sourceCaptionRaw: draft.sourceCaptionRaw.nonEmptyValue,
                sourcePostedAt: draft.sourcePostedAt,
                sourceApplyEmailExtracted: draft.sourceApplyEmailExtracted.nonEmptyValue,
                isPublished: draft.isPublished,
                session: session
            )
        }
        if error == nil {
            Task { try? await refreshAdminData() }
        }
        return error
    }

    func createEmployerJob(draft: JobPostingDraft, localVideoURL: URL) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let uploadURL = try await VideoProcessing.prepareVideoForUpload(localVideoURL)
            let fileName = uploadURL.lastPathComponent
            let videoData = try Data(contentsOf: uploadURL)

            let upload = try await service.uploadFile(
                bucket: "job-videos",
                path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                data: videoData,
                contentType: mimeType(for: uploadURL) ?? "video/mp4",
                session: session
            )

            try await service.createJob(
                employerProfileID: userID,
                title: draft.title,
                companyName: draft.companyName,
                location: draft.location,
                compensationMinAnnual: normalizedAnnualCompensation(from: draft.compensationMinAnnual),
                compensationMaxAnnual: normalizedAnnualCompensation(from: draft.compensationMaxAnnual),
                compensationMinHourly: normalizedHourlyCompensation(from: draft.compensationMinHourly),
                compensationMaxHourly: normalizedHourlyCompensation(from: draft.compensationMaxHourly),
                employmentType: draft.employmentType,
                jobFunction: draft.jobFunction,
                description: draft.description,
                applicationEmail: draft.applicationEmail,
                videoURL: upload.publicURL,
                sourceURL: draft.sourceURL,
                sourcePlatform: draft.sourcePlatform,
                sourceCreatorName: draft.sourceCreatorName.nonEmptyValue,
                sourceCreatorURL: draft.sourceCreatorURL.nonEmptyValue,
                sourceThumbnailURL: draft.sourceThumbnailURL.nonEmptyValue,
                sourceCaption: draft.sourceCaption.nonEmptyValue,
                sourceCaptionRaw: draft.sourceCaptionRaw.nonEmptyValue,
                sourcePostedAt: draft.sourcePostedAt,
                sourceApplyEmailExtracted: draft.sourceApplyEmailExtracted.nonEmptyValue,
                isPublished: draft.isPublished,
                session: session
            )

            try await refreshEmployerData()
        }
    }

    func toggleJobPublishState(jobID: String, isPublished: Bool) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            try await service.updateJobPublishState(jobID: jobID, isPublished: isPublished, session: session)

            switch role {
            case .admin:
                try await refreshAdminData()
            case .employer:
                try await refreshEmployerData()
            default:
                break
            }
        }
    }

    func reachOutToCandidate(candidateID: String, relatedJobID: String?, subject: String, message: String) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            _ = try await service.reachOutToCandidate(
                candidateID: candidateID,
                relatedJobID: relatedJobID,
                subject: subject,
                message: message,
                session: session
            )
            try await refreshEmployerData()
            try await loadNotifications()
        }
    }

    func refreshCurrentRoleData() async {
        await runBusyTask { [self] in
            try await loadCurrentUserState()
        }
    }

    func parseSharedJobPosting(sourceURL: String) async throws -> ImportedJobSuggestion {
        let session = try await requireSession()
        return try await service.parseSharedJobPosting(sourceURL: sourceURL, session: session)
    }

    func markNotificationsRead() async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let unreadIDs = notifications.filter { $0.readAt == nil }.map(\.id)
            try await service.markNotificationsRead(ids: unreadIDs, session: session)
            try await loadNotifications()
        }
    }

    private func loadCurrentUserState() async throws {
        let session = try await requireSession()
        let validSession = try await auth.ensureValidSession(session)
        self.session = validSession
        try persistSessionIfNeeded()

        let userID = validSession.user.id
        profile = try await service.fetchProfile(userID: userID, session: validSession)
        jobSeekerProfile = try await candidate.fetchJobSeekerProfile(userID: userID, session: validSession)
        employerProfile = try await service.fetchEmployerProfile(userID: userID, session: validSession)
        jobSeekerEmployers = try await candidate.fetchJobSeekerEmployers(userID: userID, session: validSession)
        latestResume = try await candidate.fetchLatestResume(userID: userID, session: validSession)

        try await loadNotifications()

        if let role = profile?.role {
            sharedDefaults?.set(role.rawValue, forKey: SharedConstants.AppGroupKeys.userRole)
            switch role {
            case .jobSeeker:
                try await refreshJobSeekerData()
            case .employer:
                try await refreshEmployerData()
            case .admin:
                try await refreshAdminData()
            }
            phase = .signedIn
        } else if profile != nil {
            try await refreshJobSeekerData()
            phase = .signedIn
        } else {
            phase = .signedOut
        }
    }

    private func refreshJobSeekerData() async throws {
        let session = try await requireSession()
        let userID = try requireUserID()
        jobFeed = try await service.fetchJobs(publishedOnly: true, session: session)
        savedJobRecords = try await candidate.fetchSavedJobs(userID: userID, session: session)
        candidateApplications = try await service.fetchJobApplications(candidateID: userID, session: session)

        // F6 For-You v0: re-rank with the user's function affinity (from
        // saves + applications) now that both are loaded. feedRank keeps the
        // other tiers stable; affinity slots between big-co and comp.
        let savedIDs = savedJobIDs
        var affinity = Set(jobFeed.filter { savedIDs.contains($0.id) }.compactMap(\.jobFunction))
        affinity.formUnion(candidateApplications.compactMap { application in
            jobFeed.first { $0.id == application.jobID }?.jobFunction
        })
        if !affinity.isEmpty {
            let now = Date()
            jobFeed = jobFeed.sorted { a, b in
                let ra = a.feedRank(now: now, affinity: affinity)
                let rb = b.feedRank(now: now, affinity: affinity)
                if ra != rb { return ra < rb }
                return a.createdAt > b.createdAt
            }
        }
    }

    private func refreshEmployerData() async throws {
        let session = try await requireSession()
        let userID = try requireUserID()
        employerJobs = try await service.fetchJobs(employerID: userID, session: session)
        employerApplications = try await service.fetchJobApplications(employerID: userID, session: session)
        discoverableCandidates = try await service.fetchDiscoverableCandidates(session: session)
        employerOutreachMessages = try await service.fetchCandidateOutreachMessages(employerID: userID, session: session)
    }

    private func refreshAdminData() async throws {
        let session = try await requireSession()
        adminJobs = try await service.fetchJobs(session: session)

        let employerProfiles = try await service.fetchEmployerProfiles(session: session)
        let profileRows = try await service.fetchProfiles(
            ids: employerProfiles.map(\.profileID),
            session: session
        )
        let profileLookup = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id, $0) })
        employerDirectoryItems = employerProfiles.compactMap { employerProfile in
            guard let profile = profileLookup[employerProfile.profileID] else { return nil }
            return EmployerDirectoryItem(
                id: employerProfile.profileID,
                fullName: profile.fullName ?? "Employer",
                email: profile.email ?? "",
                companyName: employerProfile.companyName ?? "Company"
            )
        }
        .sorted { $0.companyName.localizedCaseInsensitiveCompare($1.companyName) == .orderedAscending }
    }

    private func loadNotifications() async throws {
        let session = try await requireSession()
        notifications = try await service.fetchNotifications(session: session)
    }

    private func uploadResumeFile(userID: String, fileURL: URL, session: AuthSession) async throws {
        let fileName = fileURL.lastPathComponent
        let data = try Data(contentsOf: fileURL)
        let upload = try await service.uploadFile(
            bucket: "resumes",
            path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
            data: data,
            contentType: mimeType(for: fileURL) ?? "application/octet-stream",
            session: session
        )
        let resumeRow = try await candidate.insertResumeUpload(userID: userID, filePath: upload.path, session: session)
        try await candidate.invokeParseResume(
            resumeID: resumeRow.id,
            rawText: ResumeTextExtractor.extractText(from: fileURL),
            session: session
        )
    }

    private func requireSession() async throws -> AuthSession {
        guard let session else { throw SupabaseServiceError.missingSession }
        let valid = try await auth.ensureValidSession(session)
        if valid.accessToken != session.accessToken {
            self.session = valid
            try persistSessionIfNeeded()
        }
        return valid
    }

    private func requireUserID() throws -> String {
        guard let id = session?.user.id else {
            throw SupabaseServiceError.missingSession
        }
        return id
    }

    private func persistSessionIfNeeded() throws {
        guard let session else {
            defaults.removeObject(forKey: sessionKey)
            sharedDefaults?.removeObject(forKey: SharedConstants.AppGroupKeys.accessToken)
            return
        }
        let data = try encoder.encode(session)
        defaults.set(data, forKey: sessionKey)
        sharedDefaults?.set(session.accessToken, forKey: SharedConstants.AppGroupKeys.accessToken)
        sharedDefaults?.set(PassportConfig.load().supabaseURL, forKey: SharedConstants.AppGroupKeys.supabaseURL)
    }

    private func loadPersistedSession() -> AuthSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    private func clearSession() {
        session = nil
        profile = nil
        jobSeekerProfile = nil
        employerProfile = nil
        jobSeekerEmployers = []
        latestResume = nil
        notifications = []
        jobFeed = []
        savedJobRecords = []
        candidateApplications = []
        employerJobs = []
        employerApplications = []
        discoverableCandidates = []
        employerOutreachMessages = []
        adminJobs = []
        employerDirectoryItems = []
        defaults.removeObject(forKey: sessionKey)
        sharedDefaults?.removeObject(forKey: SharedConstants.AppGroupKeys.accessToken)
        sharedDefaults?.removeObject(forKey: SharedConstants.AppGroupKeys.userRole)
    }

    private func runBusyTask(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = SupabaseErrorMapping.friendlyMessage(for: error)
        }
        isBusy = false
    }

    private func runBusyTaskReturningError(_ operation: @escaping () async throws -> Void) async -> String? {
        isBusy = true
        errorMessage = nil
        do {
            try await operation()
            isBusy = false
            return nil
        } catch {
            let message = SupabaseErrorMapping.friendlyMessage(for: error)
            errorMessage = message
            isBusy = false
            return message
        }
    }

    private func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        case "mp4":
            return "video/mp4"
        case "m4v":
            return "video/x-m4v"
        case "pdf":
            return "application/pdf"
        case "txt":
            return "text/plain"
        case "rtf":
            return "application/rtf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc":
            return "application/msword"
        default:
            return nil
        }
    }

    private func normalizedAnnualCompensation(from rawValue: String) -> Int? {
        let digits = rawValue.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private func normalizedHourlyCompensation(from rawValue: String) -> Int? {
        let digits = rawValue.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private func mappedCompensationRange(from annualValue: Int?) -> String {
        guard let annualValue else { return "" }
        switch annualValue {
        case ..<50_000:
            return "Under $50k"
        case 50_000..<75_000:
            return "$50k-$75k"
        case 75_000..<100_000:
            return "$75k-$100k"
        case 100_000..<125_000:
            return "$100k-$125k"
        case 125_000..<150_000:
            return "$125k-$150k"
        case 150_000..<175_000:
            return "$150k-$175k"
        case 175_000..<200_000:
            return "$175k-$200k"
        default:
            return "$200k+"
        }
    }

    private func normalizedOptionalURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return trimmed
        }

        return "https://\(trimmed)"
    }

    private func normalizedUsername(_ rawValue: String) -> String? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

private func normalizedHandle(_ rawValue: String) -> String? {
        let handle = SharedFormatters.profileHandle(rawValue)
        guard !handle.isEmpty else { return nil }
        return String(handle.prefix(30))
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
