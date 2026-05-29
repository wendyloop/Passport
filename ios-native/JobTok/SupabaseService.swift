import Foundation

enum SocialAuthProvider: String {
    case google
    case apple
}

struct StorageUploadResult {
    let path: String
    let publicURL: String
}

enum SupabaseServiceError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case missingSession
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Supabase is not configured in the native app target."
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case .missingSession:
            return "You need to be signed in."
        case .apiError(let message):
            return message
        }
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    private let config = PassportConfig.load()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    var isConfigured: Bool {
        config.supabaseURL.hasPrefix("http")
            && !config.supabaseAnonKey.isEmpty
            && !config.isPlaceholderURL
            && !config.isPlaceholderKey
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try validateConfiguration()
        let response: AuthSessionEnvelope = try await authRequest(
            path: "signup",
            method: "POST",
            body: [
                "email": email,
                "password": password
            ]
        )

        guard let session = response.session else {
            throw SupabaseServiceError.apiError(
                "Supabase sign-up succeeded, but no session was returned. Disable email confirmation in Supabase Auth if you want immediate access in the app."
            )
        }

        return session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try validateConfiguration()
        let request = try makeRequest(
            url: authURL(path: "token", query: [("grant_type", "password")]),
            method: "POST",
            body: [
                "email": email,
                "password": password
            ]
        )
        let envelope = try await execute(request, decode: AuthSessionEnvelope.self)
        guard let session = envelope.session else {
            throw SupabaseServiceError.invalidResponse
        }
        return session
    }

    func oauthAuthorizationURL(provider: SocialAuthProvider, redirectTo: URL) throws -> URL {
        try validateConfiguration()
        return authURL(
            path: "authorize",
            query: [
                ("provider", provider.rawValue),
                ("redirect_to", redirectTo.absoluteString)
            ]
        )
    }

    func sendMagicLink(email: String, redirectTo: URL) async throws {
        try validateConfiguration()
        let request = try makeRequest(
            url: authBaseURL.appendingPathComponent("otp"),
            method: "POST",
            body: [
                "email": AnyEncodable(email),
                "create_user": AnyEncodable(true),
                "email_redirect_to": AnyEncodable(redirectTo.absoluteString)
            ] as [String : AnyEncodable]
        )
        _ = try await executeData(request)
    }

    func session(fromAuthRedirectURL url: URL) async throws -> AuthSession {
        let parameters = authCallbackParameters(from: url)

        if let errorDescription = parameters["error_description"] {
            throw SupabaseServiceError.apiError(errorDescription)
        }
        if let errorMessage = parameters["error"] {
            throw SupabaseServiceError.apiError(errorMessage)
        }
        if parameters["code"] != nil {
            throw SupabaseServiceError.apiError("Supabase returned an authorization code instead of a session token. Confirm the provider redirect is configured for the native deep link flow.")
        }

        guard
            let accessToken = parameters["access_token"],
            let refreshToken = parameters["refresh_token"]
        else {
            throw SupabaseServiceError.apiError("Supabase did not return a valid session in the callback URL.")
        }

        let expiresAt: Date
        if let expiresAtEpoch = parameters["expires_at"].flatMap(Double.init) {
            expiresAt = Date(timeIntervalSince1970: expiresAtEpoch)
        } else if let expiresIn = parameters["expires_in"].flatMap(Double.init) {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }

        let user = try await fetchAuthUser(accessToken: accessToken)
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: user
        )
    }

    func refreshSession(_ session: AuthSession) async throws -> AuthSession {
        try validateConfiguration()
        let request = try makeRequest(
            url: authURL(path: "token", query: [("grant_type", "refresh_token")]),
            method: "POST",
            body: [
                "refresh_token": session.refreshToken
            ]
        )
        let envelope = try await execute(request, decode: AuthSessionEnvelope.self)
        guard let session = envelope.session else {
            throw SupabaseServiceError.invalidResponse
        }
        return session
    }

    func ensureValidSession(_ session: AuthSession) async throws -> AuthSession {
        if session.expiresAt.timeIntervalSinceNow > 60 {
            return session
        }
        return try await refreshSession(session)
    }

    func signOut(session: AuthSession) async {
        guard isConfigured else { return }
        do {
            let request = try makeRequest(
                url: authBaseURL.appendingPathComponent("logout"),
                method: "POST",
                accessToken: session.accessToken,
                body: ["scope": "global"]
            )
            _ = try await executeData(request)
        } catch {
            // Best effort only.
        }
    }

    func fetchProfile(userID: String, session: AuthSession) async throws -> AppProfileRecord? {
        try await selectSingle(
            path: "profiles",
            query: [
                ("id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchJobSeekerProfile(userID: String, session: AuthSession) async throws -> JobSeekerProfileRecord? {
        try await selectSingle(
            path: "job_seeker_profiles",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchEmployerProfile(userID: String, session: AuthSession) async throws -> EmployerProfileRecord? {
        try await selectSingle(
            path: "employer_profiles",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchEmployerProfiles(session: AuthSession) async throws -> [EmployerProfileRecord] {
        try await selectArray(
            path: "employer_profiles",
            query: [
                ("select", "*"),
                ("order", "company_name.asc")
            ],
            session: session
        )
    }

    func fetchProfiles(ids: [String], session: AuthSession) async throws -> [AppProfileRecord] {
        guard !ids.isEmpty else { return [] }
        return try await selectArray(
            path: "profiles",
            query: [
                ("id", "in.(\(ids.joined(separator: ",")))"),
                ("select", "id,role,full_name,email,headline,onboarding_complete")
            ],
            session: session
        )
    }

    func fetchProfiles(role: UserRole, session: AuthSession) async throws -> [AppProfileRecord] {
        try await selectArray(
            path: "profiles",
            query: [
                ("role", "eq.\(role.rawValue)"),
                ("select", "id,role,full_name,email,headline,onboarding_complete"),
                ("order", "full_name.asc")
            ],
            session: session
        )
    }

    func fetchJobSeekerEmployers(userID: String, session: AuthSession) async throws -> [JobSeekerEmployerRecord] {
        try await selectArray(
            path: "job_seeker_employers",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "sort_order.asc")
            ],
            session: session
        )
    }

    func fetchLatestResume(userID: String, session: AuthSession) async throws -> ResumeUploadRecord? {
        try await selectSingle(
            path: "resume_uploads",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "created_at.desc"),
                ("limit", "1")
            ],
            session: session
        )
    }

    func fetchNotifications(session: AuthSession) async throws -> [NotificationRecord] {
        try await selectArray(
            path: "notifications",
            query: [
                ("select", "id,title,body,created_at,read_at"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    func fetchJobs(publishedOnly: Bool = false, employerID: String? = nil, session: AuthSession) async throws -> [JobPostingRecord] {
        var query: [(String, String)] = [
            ("select", "*"),
            ("order", "created_at.desc")
        ]
        if publishedOnly {
            query.append(("is_published", "eq.true"))
        }
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        return try await selectArray(path: "jobs", query: query, session: session)
    }

    func fetchJobApplications(candidateID: String? = nil, employerID: String? = nil, session: AuthSession) async throws -> [JobApplicationRecord] {
        var query: [(String, String)] = [
            ("select", "*"),
            ("order", "applied_at.desc")
        ]
        if let candidateID {
            query.append(("candidate_profile_id", "eq.\(candidateID)"))
        }
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        return try await selectArray(path: "job_applications", query: query, session: session)
    }

    func fetchSavedJobs(userID: String, session: AuthSession) async throws -> [SavedJobRecord] {
        try await selectArray(
            path: "saved_jobs",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    func fetchDiscoverableCandidates(session: AuthSession) async throws -> [DiscoverableCandidateRecord] {
        try await selectArray(
            path: "employer_candidate_discovery",
            query: [
                ("select", "*"),
                ("order", "full_name.asc")
            ],
            session: session
        )
    }

    func fetchCandidateOutreachMessages(employerID: String? = nil, session: AuthSession) async throws -> [CandidateOutreachRecord] {
        var query: [(String, String)] = [
            ("select", "*"),
            ("order", "created_at.desc")
        ]
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        return try await selectArray(path: "candidate_outreach_messages", query: query, session: session)
    }

    func upsertProfile(
        userID: String,
        email: String?,
        fullName: String,
        handle: String?,
        avatarURL: String? = nil,
        includeAvatarURL: Bool = false,
        headline: String,
        onboardingComplete: Bool,
        session: AuthSession
    ) async throws {
        var row: [String: AnyEncodable] = [
            "id": AnyEncodable(userID),
            "email": AnyEncodable(email),
            "full_name": AnyEncodable(fullName),
            "handle": AnyEncodable(handle),
            "headline": AnyEncodable(headline),
            "onboarding_complete": AnyEncodable(onboardingComplete)
        ]
        if includeAvatarURL {
            row["avatar_url"] = AnyEncodable(avatarURL)
        }
        let body = [row]

        _ = try await postgrestWrite(
            path: "profiles",
            method: "POST",
            query: [("on_conflict", "id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func upsertJobSeekerProfile(
        userID: String,
        schoolName: String,
        jobFunction: JobFunctionOption,
        dreamRole: String,
        desiredCompensationAnnual: Int?,
        desiredCompensationRange: String?,
        linkedInURL: String?,
        instagramUsername: String?,
        tiktokUsername: String?,
        introVideoURL: String?,
        visibility: CandidateVisibility,
        session: AuthSession
    ) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "school_name": AnyEncodable(schoolName),
            "job_function": AnyEncodable(jobFunction.rawValue),
            "dream_role": AnyEncodable(dreamRole.isEmpty ? nil : dreamRole),
            "desired_compensation_annual": AnyEncodable(desiredCompensationAnnual),
            "desired_compensation_range": AnyEncodable(desiredCompensationRange),
            "linkedin_url": AnyEncodable(linkedInURL),
            "instagram_username": AnyEncodable(instagramUsername),
            "tiktok_username": AnyEncodable(tiktokUsername),
            "intro_video_url": AnyEncodable(introVideoURL),
            "discovery_visibility": AnyEncodable(visibility.rawValue)
        ]]

        _ = try await postgrestWrite(
            path: "job_seeker_profiles",
            method: "POST",
            query: [("on_conflict", "profile_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func upsertEmployerProfile(
        userID: String,
        companyName: String,
        companyDomain: String,
        positionTitle: String,
        session: AuthSession
    ) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "company_name": AnyEncodable(companyName),
            "company_domain": AnyEncodable(companyDomain),
            "position_title": AnyEncodable(positionTitle)
        ]]

        _ = try await postgrestWrite(
            path: "employer_profiles",
            method: "POST",
            query: [("on_conflict", "profile_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func replaceJobSeekerEmployers(userID: String, employers: [String], session: AuthSession) async throws {
        try await delete(
            path: "job_seeker_employers",
            query: [("profile_id", "eq.\(userID)")],
            session: session
        )

        guard !employers.isEmpty else { return }

        let body = employers.enumerated().map { index, employer in
            [
                "profile_id": AnyEncodable(userID),
                "employer_name": AnyEncodable(employer),
                "sort_order": AnyEncodable(index + 1)
            ]
        }

        _ = try await postgrestWrite(path: "job_seeker_employers", method: "POST", body: body, session: session) as EmptyPayload
    }

    func insertCandidateVideo(userID: String, publicURL: String, durationSeconds: Int?, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "video_url": AnyEncodable(publicURL),
            "duration_seconds": AnyEncodable(durationSeconds)
        ]]

        _ = try await postgrestWrite(path: "candidate_videos", method: "POST", body: body, session: session) as EmptyPayload
    }

    func insertResumeUpload(userID: String, filePath: String, session: AuthSession) async throws -> ResumeUploadRecord {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "file_path": AnyEncodable(filePath)
        ]]

        let records: [ResumeUploadRecord] = try await postgrestWrite(
            path: "resume_uploads",
            method: "POST",
            body: body,
            session: session,
            prefer: "return=representation"
        )
        guard let record = records.first else { throw SupabaseServiceError.invalidResponse }
        return record
    }

    func saveJob(userID: String, jobID: String, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "job_id": AnyEncodable(jobID)
        ]]

        _ = try await postgrestWrite(
            path: "saved_jobs",
            method: "POST",
            query: [("on_conflict", "profile_id,job_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func unsaveJob(userID: String, jobID: String, session: AuthSession) async throws {
        try await delete(
            path: "saved_jobs",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("job_id", "eq.\(jobID)")
            ],
            session: session
        )
    }

    func invokeParseResume(resumeID: String, rawText: String?, session: AuthSession) async throws {
        var body: [String: AnyEncodable] = ["resumeId": AnyEncodable(resumeID)]
        if let rawText, !rawText.isEmpty {
            body["rawText"] = AnyEncodable(rawText)
        }

        let request = try makeRequest(
            url: functionsBaseURL.appendingPathComponent("parse-resume"),
            method: "POST",
            accessToken: session.accessToken,
            body: body
        )
        _ = try await executeData(request)
    }

    func uploadFile(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        session: AuthSession,
        upsert: Bool = true
    ) async throws -> StorageUploadResult {
        let encodedPath = path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")

        var request = try makeRequest(
            url: URL(string: "\(storageBaseURL.absoluteString)/object/\(bucket)/\(encodedPath)")!,
            method: "POST",
            accessToken: session.accessToken
        )
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(upsert ? "true" : "false", forHTTPHeaderField: "x-upsert")

        _ = try await executeData(request)

        let publicURL = storageBaseURL
            .appendingPathComponent("object/public/\(bucket)/\(encodedPath)")
            .absoluteString

        return StorageUploadResult(path: path, publicURL: publicURL)
    }

    func createJob(
        employerProfileID: String?,
        title: String,
        companyName: String,
        location: String,
        compensationMinAnnual: Int?,
        compensationMaxAnnual: Int?,
        compensationMinHourly: Int?,
        compensationMaxHourly: Int?,
        employmentType: EmploymentTypeOption?,
        jobFunction: JobFunctionOption,
        description: String,
        applicationEmail: String,
        videoURL: String,
        sourceURL: String?,
        sourcePlatform: SocialSourcePlatform?,
        sourceCreatorName: String?,
        sourceCreatorURL: String?,
        sourceThumbnailURL: String?,
        sourceCaption: String?,
        sourceCaptionRaw: String?,
        sourcePostedAt: Date?,
        sourceApplyEmailExtracted: String?,
        isPublished: Bool,
        session: AuthSession
    ) async throws {
        let userID = session.user.id
        let body: [[String: AnyEncodable]] = [[
            "employer_profile_id": AnyEncodable(employerProfileID),
            "posted_by_profile_id": AnyEncodable(userID),
            "title": AnyEncodable(title),
            "company_name": AnyEncodable(companyName),
            "location": AnyEncodable(location.isEmpty ? nil : location),
            "compensation_min_annual": AnyEncodable(compensationMinAnnual),
            "compensation_max_annual": AnyEncodable(compensationMaxAnnual),
            "compensation_min_hourly": AnyEncodable(compensationMinHourly),
            "compensation_max_hourly": AnyEncodable(compensationMaxHourly),
            "employment_type": AnyEncodable(employmentType?.rawValue),
            "job_function": AnyEncodable(jobFunction.rawValue),
            "description": AnyEncodable(description),
            "application_email": AnyEncodable(applicationEmail),
            "video_url": AnyEncodable(videoURL),
            "source_url": AnyEncodable(sourceURL?.isEmpty == true ? nil : sourceURL),
            "source_platform": AnyEncodable(sourcePlatform?.rawValue),
            "source_creator_name": AnyEncodable(sourceCreatorName?.isEmpty == true ? nil : sourceCreatorName),
            "source_creator_url": AnyEncodable(sourceCreatorURL?.isEmpty == true ? nil : sourceCreatorURL),
            "source_thumbnail_url": AnyEncodable(sourceThumbnailURL?.isEmpty == true ? nil : sourceThumbnailURL),
            "source_caption": AnyEncodable(sourceCaption?.isEmpty == true ? nil : sourceCaption),
            "source_caption_raw": AnyEncodable(sourceCaptionRaw?.isEmpty == true ? nil : sourceCaptionRaw),
            "source_posted_at": AnyEncodable(sourcePostedAt),
            "source_apply_email_extracted": AnyEncodable(sourceApplyEmailExtracted?.isEmpty == true ? nil : sourceApplyEmailExtracted),
            "is_published": AnyEncodable(isPublished)
        ]]

        _ = try await postgrestWrite(path: "jobs", method: "POST", body: body, session: session, prefer: "return=minimal") as EmptyPayload
    }

    func parseSharedJobPosting(sourceURL: String, session: AuthSession) async throws -> ImportedJobSuggestion {
        let request = try makeRequest(
            url: functionsBaseURL.appendingPathComponent("parse-shared-job-posting"),
            method: "POST",
            accessToken: session.accessToken,
            body: ["sourceURL": AnyEncodable(sourceURL)]
        )
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let envelope = try decoder.decode(ImportedJobSuggestionEnvelope.self, from: data)
            return envelope.suggestion
        } catch let decodeError {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 data>"
            throw SupabaseServiceError.apiError("HTTP \(statusCode)\n\nDecode error: \(decodeError.localizedDescription)\n\nRaw response:\n\(rawBody.prefix(2000))")
        }
    }

    func updateJobPublishState(jobID: String, isPublished: Bool, session: AuthSession) async throws {
        let body: [String: AnyEncodable] = [
            "is_published": AnyEncodable(isPublished)
        ]
        let _: EmptyPayload = try await patchSingle(
            path: "jobs",
            query: [("id", "eq.\(jobID)")],
            body: body,
            session: session
        )
    }

    func applyToJob(draft: JobApplicationDraft, session: AuthSession) async throws -> JobApplicationRecord {
        let request = try makeRequest(
            url: functionsBaseURL.appendingPathComponent("apply-to-job"),
            method: "POST",
            accessToken: session.accessToken,
            body: [
                "jobId": AnyEncodable(draft.jobID),
                "resumeFilePath": AnyEncodable(draft.resumeFilePath),
                "selectedVideoURL": AnyEncodable(draft.includePitchVideo ? draft.pitchVideoURL : nil),
                "socialLink": AnyEncodable(draft.sharedSocialLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.sharedSocialLink.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
        )
        let response = try await execute(request, decode: JobApplicationEnvelope.self)
        return response.application
    }

    func reachOutToCandidate(
        candidateID: String,
        relatedJobID: String?,
        subject: String,
        message: String,
        session: AuthSession
    ) async throws -> CandidateOutreachRecord {
        let request = try makeRequest(
            url: functionsBaseURL.appendingPathComponent("reach-out-to-candidate"),
            method: "POST",
            accessToken: session.accessToken,
            body: [
                "candidateId": AnyEncodable(candidateID),
                "relatedJobId": AnyEncodable(relatedJobID),
                "subject": AnyEncodable(subject),
                "message": AnyEncodable(message)
            ]
        )
        let response = try await execute(request, decode: CandidateOutreachEnvelope.self)
        return response.outreach
    }

    func deleteAccount(session: AuthSession) async throws {
        let request = try makeRequest(
            url: functionsBaseURL.appendingPathComponent("delete-account"),
            method: "POST",
            accessToken: session.accessToken,
            body: [:] as [String: String]
        )
        _ = try await executeData(request)
    }

    func createSignedFileURL(
        bucket: String,
        path: String,
        expiresIn: Int,
        session: AuthSession
    ) async throws -> URL {
        let encodedPath = path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")

        let request = try makeRequest(
            url: URL(string: "\(storageBaseURL.absoluteString)/object/sign/\(bucket)/\(encodedPath)")!,
            method: "POST",
            accessToken: session.accessToken,
            body: ["expiresIn": AnyEncodable(expiresIn)]
        )
        let response = try await execute(request, decode: StorageSignedURLEnvelope.self)
        if let absolute = URL(string: response.signedURL), absolute.scheme != nil {
            return absolute
        }
        let normalized = response.signedURL.hasPrefix("/") ? String(response.signedURL.dropFirst()) : response.signedURL
        return storageBaseURL.appendingPathComponent(normalized)
    }

    func markNotificationsRead(ids: [String]?, session: AuthSession) async throws {
        let payload = ids.map { ids in ids.map(AnyEncodable.init) }
        let _: Int = try await rpc(
            function: "mark_notifications_read",
            parameters: [
                "p_notification_ids": AnyEncodable(payload)
            ],
            session: session
        )
    }

    func delete(path: String, query: [(String, String)], session: AuthSession) async throws {
        let request = try makeRestRequest(
            path: path,
            query: query,
            method: "DELETE",
            accessToken: session.accessToken
        )
        _ = try await executeData(request)
    }

    private func authRequest<T: Decodable>(path: String, method: String, body: [String: String]) async throws -> T {
        let request = try makeRequest(url: authBaseURL.appendingPathComponent(path), method: method, body: body)
        return try await execute(request, decode: T.self)
    }

    private func fetchAuthUser(accessToken: String) async throws -> AuthUser {
        let request = try makeRequest(
            url: authBaseURL.appendingPathComponent("user"),
            method: "GET",
            accessToken: accessToken
        )
        return try await execute(request, decode: AuthUser.self)
    }

    private func authCallbackParameters(from url: URL) -> [String: String] {
        var values: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                values[item.name] = item.value
            }
        }

        if let fragment = url.fragment,
           let components = URLComponents(string: "jobtok://callback?\(fragment)") {
            for item in components.queryItems ?? [] {
                values[item.name] = item.value
            }
        }

        return values
    }

    private func rpc<T: Decodable>(
        function: String,
        parameters: [String: AnyEncodable],
        session: AuthSession
    ) async throws -> T {
        let request = try makeRestRequest(
            path: "rpc/\(function)",
            method: "POST",
            accessToken: session.accessToken,
            body: parameters
        )
        return try await execute(request, decode: T.self)
    }

    private func postgrestWrite<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [(String, String)] = [],
        body: Body,
        session: AuthSession,
        prefer: String? = nil
    ) async throws -> T {
        var request = try makeRestRequest(
            path: path,
            query: query,
            method: method,
            accessToken: session.accessToken,
            body: body
        )
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        return try await execute(request, decode: T.self)
    }

    private func patchSingle<T: Decodable, Body: Encodable>(
        path: String,
        query: [(String, String)],
        body: Body,
        session: AuthSession
    ) async throws -> T {
        var request = try makeRestRequest(
            path: path,
            query: query,
            method: "PATCH",
            accessToken: session.accessToken,
            body: body
        )
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return try await execute(request, decode: T.self)
    }

    private func selectSingle<T: Decodable>(
        path: String,
        query: [(String, String)],
        session: AuthSession
    ) async throws -> T? {
        let items: [T] = try await selectArray(path: path, query: query, session: session)
        return items.first
    }

    private func selectArray<T: Decodable>(
        path: String,
        query: [(String, String)],
        session: AuthSession
    ) async throws -> [T] {
        let request = try makeRestRequest(
            path: path,
            query: query,
            method: "GET",
            accessToken: session.accessToken
        )
        return try await execute(request, decode: [T].self)
    }

    private func execute<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        let data = try await executeData(request)
        if T.self == EmptyPayload.self {
            return EmptyPayload() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if let apiError = try? decoder.decode(SupabaseAPIError.self, from: data) {
                throw SupabaseServiceError.apiError(apiError.message)
            }
            throw error
        }
    }

    private func executeData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let apiError = try? decoder.decode(SupabaseAPIError.self, from: data) {
                throw SupabaseServiceError.apiError(apiError.message)
            }
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                throw SupabaseServiceError.apiError(body)
            }
            throw SupabaseServiceError.apiError("Supabase request failed with status \(httpResponse.statusCode).")
        }
        return data
    }

    private func makeRestRequest(
        path: String,
        query: [(String, String)] = [],
        method: String,
        accessToken: String
    ) throws -> URLRequest {
        try makeRequest(
            url: restURL(path: path, query: query),
            method: method,
            accessToken: accessToken
        )
    }

    private func makeRestRequest<Body: Encodable>(
        path: String,
        query: [(String, String)] = [],
        method: String,
        accessToken: String,
        body: Body
    ) throws -> URLRequest {
        try makeRequest(
            url: restURL(path: path, query: query),
            method: method,
            accessToken: accessToken,
            body: body
        )
    }

    private func makeRequest(
        url: URL,
        method: String,
        accessToken: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeRequest<Body: Encodable>(
        url: URL,
        method: String,
        accessToken: String? = nil,
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(url: url, method: method, accessToken: accessToken)
        request.httpBody = try encoder.encode(body)
        return request
    }

    private var authBaseURL: URL {
        URL(string: "\(config.supabaseURL)/auth/v1")!
    }

    private var restBaseURL: URL {
        URL(string: "\(config.supabaseURL)/rest/v1")!
    }

    private var storageBaseURL: URL {
        URL(string: "\(config.supabaseURL)/storage/v1")!
    }

    private var functionsBaseURL: URL {
        URL(string: "\(config.supabaseURL)/functions/v1")!
    }

    private func restURL(path: String, query: [(String, String)]) -> URL {
        var components = URLComponents(url: restBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components?.url ?? restBaseURL.appendingPathComponent(path)
    }

    private func authURL(path: String, query: [(String, String)]) -> URL {
        var components = URLComponents(url: authBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components?.url ?? authBaseURL.appendingPathComponent(path)
    }

    private func validateConfiguration() throws {
        guard isConfigured else {
            throw SupabaseServiceError.invalidConfiguration
        }
    }
}

private struct EmptyPayload: Codable {}

private struct SupabaseAPIError: Codable {
    let message: String
}

private struct AuthSessionEnvelope: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
    let expiresIn: Int?
    let user: AuthUser?

    var session: AuthSession? {
        guard
            let accessToken,
            let refreshToken,
            let user
        else {
            return nil
        }

        let expiry = expiresAt ?? Date().addingTimeInterval(TimeInterval(expiresIn ?? 3600))
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            user: user
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        user = try container.decodeIfPresent(AuthUser.self, forKey: .user)

        if let epoch = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let epochInt = try container.decodeIfPresent(Int.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(epochInt))
        } else if let dateString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: dateString)
        } else {
            expiresAt = nil
        }
    }
}

private struct JobApplicationEnvelope: Codable {
    let application: JobApplicationRecord
}

private struct CandidateOutreachEnvelope: Codable {
    let outreach: CandidateOutreachRecord
}

private struct ImportedJobSuggestionEnvelope: Codable {
    let suggestion: ImportedJobSuggestion
}

private struct StorageSignedURLEnvelope: Codable {
    let signedURL: String

    enum CodingKeys: String, CodingKey {
        case signedURL = "signedURL"
    }
}

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T?) {
        self.encodeClosure = { encoder in
            var container = encoder.singleValueContainer()
            if let value {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
