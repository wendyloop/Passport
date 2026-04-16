import Foundation
import PDFKit

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
    @Published private(set) var employerFeedRecords: [CandidateFeedRecord] = []
    @Published private(set) var likedFeedRecords: [CandidateFeedRecord] = []
    @Published private(set) var employerAvailabilitySlots: [AvailabilitySlotRecord] = []
    @Published private(set) var employerPendingRequests: [InterviewRequestRecord] = []
    @Published private(set) var jobSeekerRequests: [InterviewRequestRecord] = []
    @Published private(set) var openSlotsByEmployer: [String: [AvailabilitySlotRecord]] = [:]
    @Published private(set) var employerDirectory: [String: EmployerProfileRecord] = [:]
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let service = SupabaseService.shared
    private let defaults = UserDefaults.standard
    private let sessionKey = "passport.supabase.session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        Task { await bootstrap() }
    }

    var isConfigured: Bool { service.isConfigured }

    var role: UserRole? {
        profile?.role
    }

    var currentUserID: String? {
        session?.user.id
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
            referred: jobSeekerProfile?.referralBadge ?? false,
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

    var employerFeed: [Candidate] {
        employerFeedRecords.map { record in
            Candidate(
                id: record.candidateID,
                name: record.fullName ?? "Candidate",
                headline: record.headline ?? "",
                school: record.schoolName ?? "School not provided",
                previousEmployers: record.previousEmployers,
                jobFunction: record.jobFunction?.title ?? "Unspecified",
                referred: record.referralBadge ?? false,
                demoVideoName: nil,
                localVideoPath: nil,
                remoteVideoURL: record.videoURL
            )
        }
    }

    var likedCandidates: [Candidate] {
        likedFeedRecords.map { record in
            Candidate(
                id: record.candidateID,
                name: record.fullName ?? "Candidate",
                headline: record.headline ?? "",
                school: record.schoolName ?? "School not provided",
                previousEmployers: record.previousEmployers,
                jobFunction: record.jobFunction?.title ?? "Unspecified",
                referred: record.referralBadge ?? false,
                demoVideoName: nil,
                localVideoPath: nil,
                remoteVideoURL: record.videoURL
            )
        }
    }

    var employerApprovalItems: [EmployerApprovalItem] {
        let candidateNames = Dictionary(uniqueKeysWithValues: employerFeed.map { ($0.id, $0.name) })
        let slotLabels = Dictionary(uniqueKeysWithValues: employerAvailabilitySlots.map { ($0.id, slotLabel($0)) })

        return employerPendingRequests.map { request in
            EmployerApprovalItem(
                id: request.id,
                candidateName: candidateNames[request.candidateProfileID] ?? "Candidate",
                status: request.status,
                slotLabel: request.availabilitySlotID.flatMap { slotLabels[$0] } ?? "No slot selected"
            )
        }
    }

    var jobSeekerRequestItems: [JobSeekerRequestItem] {
        jobSeekerRequests.map { request in
            JobSeekerRequestItem(
                id: request.id,
                employerName: employerDirectory[request.employerProfileID]?.companyName ?? request.employerProfileID,
                status: request.status,
                employerProfileID: request.employerProfileID,
                availabilitySlotID: request.availabilitySlotID
            )
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
            let session = try await self.service.signUp(email: email, password: password)
            self.session = session
            try self.persistSessionIfNeeded()
            try await self.loadCurrentUserState()
        }
    }

    func signIn(email: String, password: String) async {
        await runBusyTask { [self] in
            let session = try await self.service.signIn(email: email, password: password)
            self.session = session
            try self.persistSessionIfNeeded()
            try await self.loadCurrentUserState()
        }
    }

    func signInWithGoogle() async {
        await runBusyTask { [self] in
            let session = try await self.service.signInWithGoogle()
            self.session = session
            try self.persistSessionIfNeeded()
            try await self.loadCurrentUserState()
        }
    }

    func signOut() async {
        if let session {
            await service.signOut(session: session)
        }
        clearSession()
        phase = .signedOut
    }

    func completeOnboarding(
        role: UserRole,
        fullName: String,
        headline: String,
        schoolName: String,
        employers: [String],
        jobFunction: JobFunctionOption,
        companyName: String,
        companyDomain: String,
        positionTitle: String,
        referralToken: String?,
        resumeURL: URL?,
        introVideoURL: URL?,
        introVideoDuration: Double?
    ) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let userID = try self.requireUserID()

            try await self.service.upsertProfile(
                userID: userID,
                email: self.currentEmail,
                role: role,
                fullName: fullName,
                headline: headline,
                onboardingComplete: true,
                session: session
            )

            switch role {
            case .jobSeeker:
                var uploadedVideoPublicURL: String? = self.jobSeekerProfile?.introVideoURL

                if let introVideoURL {
                    let videoData = try Data(contentsOf: introVideoURL)
                    let fileName = introVideoURL.lastPathComponent
                    let result = try await self.service.uploadFile(
                        bucket: "videos",
                        path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                        data: videoData,
                        contentType: self.mimeType(for: introVideoURL) ?? "video/quicktime",
                        session: session
                    )
                    uploadedVideoPublicURL = result.publicURL
                    try await self.service.insertCandidateVideo(
                        userID: userID,
                        publicURL: result.publicURL,
                        durationSeconds: introVideoDuration.map { Int($0.rounded()) },
                        session: session
                    )
                }

                try await self.service.upsertJobSeekerProfile(
                    userID: userID,
                    schoolName: schoolName,
                    jobFunction: jobFunction,
                    introVideoURL: uploadedVideoPublicURL,
                    session: session
                )
                try await self.service.replaceJobSeekerEmployers(userID: userID, employers: employers, session: session)

                if let resumeURL {
                    let resumeData = try Data(contentsOf: resumeURL)
                    let fileName = resumeURL.lastPathComponent
                    let upload = try await self.service.uploadFile(
                        bucket: "resumes",
                        path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                        data: resumeData,
                        contentType: self.mimeType(for: resumeURL) ?? "application/octet-stream",
                        session: session
                    )
                    let resumeRow = try await self.service.insertResumeUpload(userID: userID, filePath: upload.path, session: session)
                    try await self.service.invokeParseResume(
                        resumeID: resumeRow.id,
                        rawText: self.extractResumeText(from: resumeURL),
                        session: session
                    )
                }

                if let referralToken, !referralToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await self.service.consumeReferralInvite(token: referralToken, session: session)
                }
            case .employer:
                try await self.service.upsertEmployerProfile(
                    userID: userID,
                    companyName: companyName,
                    companyDomain: companyDomain,
                    positionTitle: positionTitle,
                    session: session
                )
            }

            try await self.loadCurrentUserState()
        }
    }

    func saveCandidateProfile(_ draft: CandidateProfileDraft) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let userID = try self.requireUserID()

            try await self.service.upsertProfile(
                userID: userID,
                email: self.currentEmail,
                role: .jobSeeker,
                fullName: draft.fullName,
                headline: draft.headline,
                onboardingComplete: true,
                session: session
            )
            try await self.service.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                introVideoURL: draft.introVideoURL,
                session: session
            )
            try await self.service.replaceJobSeekerEmployers(userID: userID, employers: draft.employers, session: session)
            try await self.loadCurrentUserState()
        }
    }

    func uploadCandidateVideo(fileURL: URL, duration: Double) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let userID = try self.requireUserID()
            let fileName = fileURL.lastPathComponent
            let videoData = try Data(contentsOf: fileURL)

            let upload = try await self.service.uploadFile(
                bucket: "videos",
                path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                data: videoData,
                contentType: self.mimeType(for: fileURL) ?? "video/quicktime",
                session: session
            )
            try await self.service.insertCandidateVideo(
                userID: userID,
                publicURL: upload.publicURL,
                durationSeconds: Int(duration.rounded()),
                session: session
            )
            let draft = self.candidateDraft
            try await self.service.upsertJobSeekerProfile(
                userID: userID,
                schoolName: draft.school,
                jobFunction: draft.jobFunction,
                introVideoURL: upload.publicURL,
                session: session
            )
            try await self.loadCurrentUserState()
        }
    }

    func uploadResume(fileURL: URL) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let userID = try self.requireUserID()
            let fileName = fileURL.lastPathComponent
            let data = try Data(contentsOf: fileURL)
            let upload = try await self.service.uploadFile(
                bucket: "resumes",
                path: "\(userID)/\(Int(Date().timeIntervalSince1970))-\(fileName)",
                data: data,
                contentType: self.mimeType(for: fileURL) ?? "application/octet-stream",
                session: session
            )
            let resumeRow = try await self.service.insertResumeUpload(userID: userID, filePath: upload.path, session: session)
            try await self.service.invokeParseResume(
                resumeID: resumeRow.id,
                rawText: self.extractResumeText(from: fileURL),
                session: session
            )
            try await self.loadCurrentUserState()
        }
    }

    func likeCandidate(candidateID: String) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            try await self.service.likeCandidate(candidateID: candidateID, session: session)
            try await self.refreshEmployerData()
            try await self.loadNotifications()
        }
    }

    func addAvailabilitySlot(startAt: Date, endAt: Date) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let userID = try self.requireUserID()
            try await self.service.addAvailabilitySlot(userID: userID, startAt: startAt, endAt: endAt, session: session)
            try await self.refreshEmployerData()
        }
    }

    func respondToInterview(requestID: String, approved: Bool) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            try await self.service.respondToInterviewRequest(requestID: requestID, approved: approved, session: session)
            try await self.refreshEmployerData()
            try await self.loadNotifications()
        }
    }

    func issueReferral(email: String?) async -> String? {
        var token: String?
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let invite = try await self.service.issueReferralInvite(email: email, session: session)
            token = invite.token
            try await self.loadNotifications()
        }
        return token
    }

    func selectInterviewSlot(requestID: String, slotID: String) async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            try await self.service.selectInterviewSlot(requestID: requestID, slotID: slotID, session: session)
            try await self.refreshJobSeekerData()
            try await self.loadNotifications()
        }
    }

    func markNotificationsRead() async {
        await runBusyTask { [self] in
            let session = try await self.requireSession()
            let unreadIDs = self.notifications.filter { $0.readAt == nil }.map(\.id)
            try await self.service.markNotificationsRead(ids: unreadIDs, session: session)
            try await self.loadNotifications()
        }
    }

    func refreshCurrentRoleData() async {
        await runBusyTask { [self] in
            try await self.loadCurrentUserState()
        }
    }

    private func loadCurrentUserState() async throws {
        let session = try await requireSession()
        let validSession = try await service.ensureValidSession(session)
        self.session = validSession
        try persistSessionIfNeeded()

        let userID = validSession.user.id
        let profile = try await service.fetchProfile(userID: userID, session: validSession)
        self.profile = profile
        self.jobSeekerProfile = try await service.fetchJobSeekerProfile(userID: userID, session: validSession)
        self.employerProfile = try await service.fetchEmployerProfile(userID: userID, session: validSession)
        self.jobSeekerEmployers = try await service.fetchJobSeekerEmployers(userID: userID, session: validSession)
        self.latestResume = try await service.fetchLatestResume(userID: userID, session: validSession)

        try await loadNotifications()

        if profile?.onboardingComplete == true, let role = profile?.role {
            switch role {
            case .employer:
                try await refreshEmployerData()
            case .jobSeeker:
                try await refreshJobSeekerData()
            }
            phase = .signedIn
        } else {
            phase = .onboarding
        }
    }

    private func refreshEmployerData() async throws {
        let session = try await requireSession()
        let userID = try requireUserID()

        employerFeedRecords = try await service.fetchCandidateFeed(session: session)

        let likes = try await service.fetchCandidateLikes(session: session)
        likedFeedRecords = try await service.fetchCandidateFeed(
            candidateIDs: likes.map(\.candidateProfileID),
            session: session
        )

        employerAvailabilitySlots = try await service.fetchAvailabilitySlots(forEmployerID: userID, session: session)
        employerPendingRequests = try await service.fetchInterviewRequests(
            for: .employer,
            userID: userID,
            status: "pending_employer_approval",
            session: session
        )
    }

    private func refreshJobSeekerData() async throws {
        let session = try await requireSession()
        let userID = try requireUserID()
        jobSeekerRequests = try await service.fetchInterviewRequests(for: .jobSeeker, userID: userID, session: session)

        let employerIDs = Array(Set(jobSeekerRequests.map(\.employerProfileID)))
        let employerProfiles = try await service.fetchEmployerProfiles(ids: employerIDs, session: session)
        employerDirectory = Dictionary(uniqueKeysWithValues: employerProfiles.map { ($0.profileID, $0) })
        var slotMap: [String: [AvailabilitySlotRecord]] = [:]
        for employerID in employerIDs {
            slotMap[employerID] = try await service.fetchAvailabilitySlots(
                forEmployerID: employerID,
                openOnly: true,
                session: session
            )
        }
        openSlotsByEmployer = slotMap
    }

    private func loadNotifications() async throws {
        let session = try await requireSession()
        notifications = try await service.fetchNotifications(session: session)
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
        employerFeedRecords = []
        likedFeedRecords = []
        employerAvailabilitySlots = []
        employerPendingRequests = []
        jobSeekerRequests = []
        openSlotsByEmployer = [:]
        employerDirectory = [:]
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

    private func slotLabel(_ slot: AvailabilitySlotRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: slot.startAt)) - \(timeString(slot.endAt))"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
