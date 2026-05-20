import Foundation
import PDFKit
@preconcurrency import AVFoundation

@MainActor
final class AppSessionStore: ObservableObject {
    private static let preferredUploadLimitBytes: Int64 = 45 * 1_024 * 1_024
    private static let hardUploadLimitBytes: Int64 = 50 * 1_024 * 1_024

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
    @Published private(set) var candidateApplications: [JobApplicationRecord] = []
    @Published private(set) var employerJobs: [JobPostingRecord] = []
    @Published private(set) var employerApplications: [JobApplicationRecord] = []
    @Published private(set) var discoverableCandidates: [DiscoverableCandidateRecord] = []
    @Published private(set) var employerOutreachMessages: [CandidateOutreachRecord] = []
    @Published private(set) var adminJobs: [JobPostingRecord] = []
    @Published private(set) var employerDirectoryItems: [EmployerDirectoryItem] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let service = SupabaseService.shared
    private let defaults = UserDefaults.standard
    private let sessionKey = "jobtok.supabase.session"
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
            headline: profile?.headline ?? "",
            school: jobSeekerProfile?.schoolName ?? latestResume?.parsedSchoolName ?? "",
            employers: jobSeekerEmployers.map(\.employerName),
            jobFunction: jobSeekerProfile?.jobFunction ?? .engineering,
            dreamRole: jobSeekerProfile?.dreamRole ?? "",
            visibility: jobSeekerProfile?.discoveryVisibility ?? .appliedRolesOnly,
            resumeFileName: latestResume?.filePath.split(separator: "/").last.map(String.init),
            resumeImportedAt: latestResume?.createdAt,
            introVideoFileName: jobSeekerProfile?.introVideoURL?.split(separator: "/").last.map(String.init),
            introVideoDuration: nil,
            introVideoURL: jobSeekerProfile?.introVideoURL
        )
    }

    var employerDraft: EmployerProfileDraft {
        EmployerProfileDraft(
            fullName: profile?.fullName ?? "",
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

    func bootstrap() async {
        if let savedSession = loadPersistedSession() {
            session = savedSession
            do {
                self.session = try await service.ensureValidSession(savedSession)
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
            let session = try await service.signUp(email: email, password: password)
            self.session = session
            try persistSessionIfNeeded()
            try await loadCurrentUserState()
        }
    }

    func signIn(email: String, password: String) async {
        await runBusyTask { [self] in
            let session = try await service.signIn(email: email, password: password)
            self.session = session
            try persistSessionIfNeeded()
            try await loadCurrentUserState()
        }
    }

    func signOut() async {
        if let session {
            await service.signOut(session: session)
        }
        clearSession()
        phase = .signedOut
    }

    func sendEmailLogin(email: String, redirectTo: URL) async -> Bool {
        var didSucceed = false
        await runBusyTask { [self] in
            try await service.sendMagicLink(email: email, redirectTo: redirectTo)
            didSucceed = true
        }
        return didSucceed
    }

    func handleAuthRedirect(url: URL) async {
        await runBusyTask { [self] in
            let session = try await service.session(fromAuthRedirectURL: url)
            self.session = session
            try persistSessionIfNeeded()
            try await loadCurrentUserState()
        }
    }

    func oauthAuthorizationURL(provider: SocialAuthProvider, redirectTo: URL) throws -> URL {
        try service.oauthAuthorizationURL(provider: provider, redirectTo: redirectTo)
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
                headline: headline,
                onboardingComplete: true,
                session: session
            )

            switch resolvedRole {
            case .jobSeeker:
                var uploadedVideoPublicURL: String? = self.jobSeekerProfile?.introVideoURL

                if let introVideoURL {
                    let uploadURL = try await prepareVideoForUpload(introVideoURL)
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
                    try await service.insertCandidateVideo(
                        userID: userID,
                        publicURL: result.publicURL,
                        durationSeconds: introVideoDuration.map { Int($0.rounded()) },
                        session: session
                    )
                }

                try await service.upsertJobSeekerProfile(
                    userID: userID,
                    schoolName: schoolName,
                    jobFunction: jobFunction,
                    dreamRole: dreamRole,
                    introVideoURL: uploadedVideoPublicURL,
                    visibility: .appliedRolesOnly,
                    session: session
                )
                try await service.replaceJobSeekerEmployers(userID: userID, employers: employers, session: session)

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
                headline: draft.headline,
                onboardingComplete: true,
                session: session
            )
            try await service.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                dreamRole: draft.dreamRole,
                introVideoURL: draft.introVideoURL,
                visibility: draft.visibility,
                session: session
            )
            try await service.replaceJobSeekerEmployers(userID: userID, employers: draft.employers, session: session)

            // Phase 2: when candidate discovery is turned on, visibility changes should
            // immediately influence employer browse queries rather than only applied-role access.

            try await loadCurrentUserState()
        }
    }

    func uploadCandidateVideo(fileURL: URL, duration: Double) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let uploadURL = try await prepareVideoForUpload(fileURL)
            let fileName = uploadURL.lastPathComponent
            let videoData = try Data(contentsOf: uploadURL)

            let upload = try await service.uploadFile(
                bucket: "videos",
                path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                data: videoData,
                contentType: mimeType(for: uploadURL) ?? "video/mp4",
                session: session
            )
            try await service.insertCandidateVideo(
                userID: userID,
                publicURL: upload.publicURL,
                durationSeconds: Int(duration.rounded()),
                session: session
            )
            let draft = candidateDraft
            try await service.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                dreamRole: draft.dreamRole,
                introVideoURL: upload.publicURL,
                visibility: draft.visibility,
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

    func applyToJob(jobID: String, coverNote: String?) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            _ = try await service.applyToJob(jobID: jobID, coverNote: coverNote, session: session)
            try await refreshJobSeekerData()
            try await loadNotifications()
        }
    }

    func createJob(draft: JobPostingDraft, localVideoURL: URL) async {
        await runBusyTask { [self] in
            let session = try await requireSession()
            let userID = try requireUserID()
            let uploadURL = try await prepareVideoForUpload(localVideoURL)
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
                employerProfileID: draft.employerProfileID,
                title: draft.title,
                companyName: draft.companyName,
                location: draft.location,
                jobFunction: draft.jobFunction,
                description: draft.description,
                applicationEmail: draft.applicationEmail,
                videoURL: upload.publicURL,
                sourceURL: draft.sourceURL,
                isPublished: draft.isPublished,
                session: session
            )

            try await refreshAdminData()
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
        let validSession = try await service.ensureValidSession(session)
        self.session = validSession
        try persistSessionIfNeeded()

        let userID = validSession.user.id
        profile = try await service.fetchProfile(userID: userID, session: validSession)
        jobSeekerProfile = try await service.fetchJobSeekerProfile(userID: userID, session: validSession)
        employerProfile = try await service.fetchEmployerProfile(userID: userID, session: validSession)
        jobSeekerEmployers = try await service.fetchJobSeekerEmployers(userID: userID, session: validSession)
        latestResume = try await service.fetchLatestResume(userID: userID, session: validSession)

        try await loadNotifications()

        if profile?.onboardingComplete == true, let role = profile?.role {
            switch role {
            case .jobSeeker:
                try await refreshJobSeekerData()
            case .employer:
                try await refreshEmployerData()
            case .admin:
                try await refreshAdminData()
            }
            phase = .signedIn
        } else {
            phase = .onboarding
        }
    }

    private func refreshJobSeekerData() async throws {
        let session = try await requireSession()
        let userID = try requireUserID()
        jobFeed = try await service.fetchJobs(publishedOnly: true, session: session)
        candidateApplications = try await service.fetchJobApplications(candidateID: userID, session: session)
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
        let resumeRow = try await service.insertResumeUpload(userID: userID, filePath: upload.path, session: session)
        try await service.invokeParseResume(
            resumeID: resumeRow.id,
            rawText: extractResumeText(from: fileURL),
            session: session
        )
    }

    private func requireSession() async throws -> AuthSession {
        guard let session else { throw SupabaseServiceError.missingSession }
        let valid = try await service.ensureValidSession(session)
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
            return
        }
        let data = try encoder.encode(session)
        defaults.set(data, forKey: sessionKey)
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
        candidateApplications = []
        employerJobs = []
        employerApplications = []
        discoverableCandidates = []
        employerOutreachMessages = []
        adminJobs = []
        employerDirectoryItems = []
        defaults.removeObject(forKey: sessionKey)
    }

    private func runBusyTask(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func prepareVideoForUpload(_ url: URL) async throws -> URL {
        let originalSize = try fileSize(for: url)
        if originalSize <= Self.preferredUploadLimitBytes {
            return url
        }

        let asset = AVURLAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw SupabaseServiceError.apiError("This video is too large to upload directly and could not be compressed.")
        }

        let outputURL = URL(filePath: NSTemporaryDirectory())
            .appending(path: "jobtok-video-\(UUID().uuidString).mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportCompressedVideo(exportSession)

        let compressedSize = try fileSize(for: outputURL)
        guard compressedSize <= Self.hardUploadLimitBytes else {
            throw SupabaseServiceError.apiError("The video is still too large after compression. Keep it under about 50 MB, or raise the Supabase Storage file size limit.")
        }

        return outputURL
    }

    private func exportCompressedVideo(_ exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? SupabaseServiceError.invalidResponse)
                case .cancelled:
                    continuation.resume(throwing: SupabaseServiceError.apiError("Video compression was cancelled."))
                default:
                    continuation.resume(throwing: SupabaseServiceError.invalidResponse)
                }
            }
        }
    }

    private func fileSize(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func extractResumeText(from url: URL) -> String? {
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "pdf", let document = PDFDocument(url: url) {
            return (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
        }

        if ["txt", "rtf"].contains(fileExtension) {
            return try? String(contentsOf: url)
        }

        return nil
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
}
