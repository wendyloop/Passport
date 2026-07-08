import Foundation

/// Candidate-side backend calls: seeker profile, resume, saved jobs, video,
/// and the apply pipeline (easy apply, ATS autofill support).
final class CandidateService {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    // MARK: - Profile

    func fetchJobSeekerProfile(userID: String, session: AuthSession) async throws -> JobSeekerProfileRecord? {
        try await transport.selectSingle(
            path: "job_seeker_profiles",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchJobSeekerEmployers(userID: String, session: AuthSession) async throws -> [JobSeekerEmployerRecord] {
        try await transport.selectArray(
            path: "job_seeker_employers",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "sort_order.asc")
            ],
            session: session
        )
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
        githubURL: String? = nil,
        portfolioURL: String? = nil,
        city: String? = nil,
        phone: String? = nil,
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
            "discovery_visibility": AnyEncodable(visibility.rawValue),
            "github_url": AnyEncodable(githubURL),
            "portfolio_url": AnyEncodable(portfolioURL),
            "city": AnyEncodable(city),
            "phone": AnyEncodable(phone),
        ]]

        _ = try await transport.postgrestWrite(
            path: "job_seeker_profiles",
            method: "POST",
            query: [("on_conflict", "profile_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func replaceJobSeekerEmployers(userID: String, employers: [String], session: AuthSession) async throws {
        try await transport.delete(
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

        _ = try await transport.postgrestWrite(path: "job_seeker_employers", method: "POST", body: body, session: session) as EmptyPayload
    }

    // MARK: - Resume

    func fetchLatestResume(userID: String, session: AuthSession) async throws -> ResumeUploadRecord? {
        try await transport.selectSingle(
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

    func insertResumeUpload(userID: String, filePath: String, session: AuthSession) async throws -> ResumeUploadRecord {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "file_path": AnyEncodable(filePath)
        ]]

        let records: [ResumeUploadRecord] = try await transport.postgrestWrite(
            path: "resume_uploads",
            method: "POST",
            body: body,
            session: session,
            prefer: "return=representation"
        )
        guard let record = records.first else { throw SupabaseServiceError.invalidResponse }
        return record
    }

    func invokeParseResume(resumeID: String, rawText: String?, session: AuthSession) async throws {
        var body: [String: AnyEncodable] = ["resumeId": AnyEncodable(resumeID)]
        if let rawText, !rawText.isEmpty {
            body["rawText"] = AnyEncodable(rawText)
        }

        let request = try transport.makeFunctionRequest(
            name: "parse-resume",
            accessToken: session.accessToken,
            body: body
        )
        _ = try await transport.executeData(request)
    }

    // MARK: - Video

    func insertCandidateVideo(userID: String, publicURL: String, durationSeconds: Int?, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "video_url": AnyEncodable(publicURL),
            "duration_seconds": AnyEncodable(durationSeconds)
        ]]

        _ = try await transport.postgrestWrite(path: "candidate_videos", method: "POST", body: body, session: session) as EmptyPayload
    }

    // MARK: - Saved jobs

    func fetchSavedJobs(userID: String, session: AuthSession) async throws -> [SavedJobRecord] {
        try await transport.selectArray(
            path: "saved_jobs",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    func saveJob(userID: String, jobID: String, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "job_id": AnyEncodable(jobID)
        ]]

        _ = try await transport.postgrestWrite(
            path: "saved_jobs",
            method: "POST",
            query: [("on_conflict", "profile_id,job_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func unsaveJob(userID: String, jobID: String, session: AuthSession) async throws {
        try await transport.delete(
            path: "saved_jobs",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("job_id", "eq.\(jobID)")
            ],
            session: session
        )
    }

    // MARK: - Apply pipeline

    func applyToJob(draft: JobApplicationDraft, session: AuthSession) async throws -> JobApplicationRecord {
        let request = try transport.makeFunctionRequest(
            name: "apply-to-job",
            accessToken: session.accessToken,
            body: [
                "jobId": AnyEncodable(draft.jobID),
                "resumeFilePath": AnyEncodable(draft.resumeFilePath),
                "selectedVideoURL": AnyEncodable(draft.includePitchVideo ? draft.pitchVideoURL : nil),
                "socialLink": AnyEncodable(draft.sharedSocialLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.sharedSocialLink.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
        )
        let response = try await transport.execute(request, decode: JobApplicationEnvelope.self)
        return response.application
    }

    func getPrefillProfile(session: AuthSession) async throws -> PrefillResponse {
        let request = try transport.makeRequest(
            url: transport.functionsBaseURL().appendingPathComponent("get-prefill-profile"),
            method: "GET",
            accessToken: session.accessToken
        )
        return try await transport.execute(request, decode: PrefillResponse.self)
    }

    func logApplicationEvent(
        jobID: String,
        eventType: String,
        applicationID: String? = nil,
        atsType: String? = nil,
        applyURL: String? = nil,
        session: AuthSession
    ) async throws -> String {
        var body: [String: AnyEncodable] = [
            "jobId": AnyEncodable(jobID),
            "eventType": AnyEncodable(eventType),
            "atsType": AnyEncodable(atsType),
            "applyUrl": AnyEncodable(applyURL),
        ]
        if let applicationID { body["applicationId"] = AnyEncodable(applicationID) }

        let request = try transport.makeFunctionRequest(
            name: "log-application-event",
            accessToken: session.accessToken,
            body: body
        )
        let response = try await transport.execute(request, decode: ApplicationEventIDEnvelope.self)
        return response.id
    }

    func storeApplicationFields(
        eventID: String,
        shortFields: [ApplicationShortField],
        essays: [ApplicationEssay],
        session: AuthSession
    ) async throws {
        let body: [String: AnyEncodable] = [
            "eventId": AnyEncodable(eventID),
            "shortFields": AnyEncodable(shortFields),
            "essays": AnyEncodable(essays),
        ]
        let request = try transport.makeFunctionRequest(
            name: "store-application-fields",
            accessToken: session.accessToken,
            body: body
        )
        _ = try await transport.executeData(request)
    }

    func matchEssayAnswer(question: String, session: AuthSession) async throws -> EssayMatch? {
        let body: [String: AnyEncodable] = [
            "question": AnyEncodable(question),
        ]
        let request = try transport.makeFunctionRequest(
            name: "match-essay-answer",
            accessToken: session.accessToken,
            body: body
        )
        let envelope = try await transport.execute(request, decode: EssayMatchEnvelope.self)
        return envelope.match
    }

    // MARK: - Founder email

    func previewFounderEmail(jobID: String, session: AuthSession) async throws -> FounderEmailPreview {
        let request = try transport.makeFunctionRequest(
            name: "send-founder-email",
            accessToken: session.accessToken,
            body: [
                "jobId": AnyEncodable(jobID),
                "mode": AnyEncodable("preview"),
            ]
        )
        return try await transport.execute(request, decode: FounderEmailPreview.self)
    }

    func sendFounderEmail(jobID: String, contactID: String?, note: String?, session: AuthSession) async throws -> FounderEmailSendResult {
        let request = try transport.makeFunctionRequest(
            name: "send-founder-email",
            accessToken: session.accessToken,
            body: [
                "jobId": AnyEncodable(jobID),
                "mode": AnyEncodable("send"),
                "contactId": AnyEncodable(contactID),
                "note": AnyEncodable(note?.isEmpty == true ? nil : note),
            ]
        )
        return try await transport.execute(request, decode: FounderEmailSendResult.self)
    }
}

private struct JobApplicationEnvelope: Codable {
    let application: JobApplicationRecord
}

private struct ApplicationEventIDEnvelope: Codable {
    let id: String
}
