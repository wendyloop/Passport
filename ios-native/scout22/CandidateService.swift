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
            // Candidate-only v0: discovery_visibility is deliberately NOT
            // written by the client — every row stays on the server default
            // (public/discoverable, set by migration 20260715120000) so the
            // future employer view launches with a full candidate pool. The
            // hidden toggle lives in JobSeekerHomeView.visibilityModeCard;
            // when it's re-surfaced, reintroduce the column write here.
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

    /// S-5: the candidate's default resume, falling back to the newest.
    /// Mirrors `_shared/resume_select.ts` — the two must agree or the resume
    /// the app attaches differs from the one the backend reasons about.
    func fetchLatestResume(userID: String, session: AuthSession) async throws -> ResumeUploadRecord? {
        try await transport.selectSingle(
            path: "resume_uploads",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "is_default.desc,created_at.desc"),
                ("limit", "1")
            ],
            session: session
        )
    }

    /// Every resume the candidate holds, default first. Backs the picker.
    func fetchResumes(userID: String, session: AuthSession) async throws -> [ResumeUploadRecord] {
        try await transport.selectArray(
            path: "resume_uploads",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "is_default.desc,created_at.desc")
            ],
            session: session
        )
    }

    /// Switching the default clears the previous one in the same statement —
    /// two client writes would briefly leave the candidate with no default,
    /// and the partial unique index would reject the second one anyway.
    func setDefaultResume(resumeID: String, session: AuthSession) async throws {
        // The RPC returns void, so there is no body to decode — executeData,
        // the same shape invokeParseResume uses for its fire-and-forget call.
        let request = try transport.makeRestRequest(
            path: "rpc/set_default_resume",
            method: "POST",
            accessToken: session.accessToken,
            body: ["p_resume_id": AnyEncodable(resumeID)]
        )
        _ = try await transport.executeData(request)
    }

    /// The candidate's own most recent resume as raw bytes, for auto-attaching
    /// to an ATS file input. The `resumes` bucket is private; its RLS policy
    /// admits the owner (`owner = auth.uid()`), so the user's own JWT suffices —
    /// no service role and no signed URL round-trip.
    func downloadLatestResume(
        session: AuthSession,
        resume: ResumeUploadRecord? = nil
    ) async throws -> (data: Data, fileName: String)? {
        // An explicit pick wins; otherwise resolve the default the same way
        // the backend does. Written out rather than with `??` — that operator
        // takes an autoclosure, which cannot be async.
        let resolved: ResumeUploadRecord?
        if let resume {
            resolved = resume
        } else {
            resolved = try await fetchLatestResume(userID: session.user.id, session: session)
        }
        guard let record = resolved, !record.filePath.isEmpty else { return nil }
        // Built by string, not appendingPathComponent: the stored path contains
        // slashes that must stay path separators rather than be escaped.
        let encoded = record.filePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? record.filePath
        guard let url = URL(string: "\(try transport.storageBaseURL().absoluteString)/object/resumes/\(encoded)")
        else { return nil }
        let request = try transport.makeRequest(url: url, method: "GET", accessToken: session.accessToken)
        let data = try await transport.executeData(request)
        guard !data.isEmpty else { return nil }
        let name = record.filePath.split(separator: "/").last.map(String.init) ?? "resume.pdf"
        return (data, name)
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

    func insertCandidateVideo(userID: String, publicURL: String, durationSeconds: Int?, caption: String?, isPrimary: Bool, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "video_url": AnyEncodable(publicURL),
            "duration_seconds": AnyEncodable(durationSeconds),
            "caption": AnyEncodable(caption),
            "is_primary": AnyEncodable(isPrimary)
        ]]

        _ = try await transport.postgrestWrite(path: "candidate_videos", method: "POST", body: body, session: session) as EmptyPayload
    }

    func fetchCandidateVideos(userID: String, session: AuthSession) async throws -> [CandidateVideoRecord] {
        try await transport.selectArray(
            path: "candidate_videos",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    func setPrimaryCandidateVideo(videoID: String, session: AuthSession) async throws {
        _ = try await transport.rpc(
            function: "set_primary_candidate_video",
            parameters: ["p_video_id": AnyEncodable(videoID)],
            session: session
        ) as EmptyPayload
    }

    func deleteCandidateVideo(videoID: String, session: AuthSession) async throws {
        _ = try await transport.rpc(
            function: "delete_candidate_video",
            parameters: ["p_video_id": AnyEncodable(videoID)],
            session: session
        ) as EmptyPayload
    }

    func updateCandidateVideoCaption(videoID: String, caption: String?, session: AuthSession) async throws {
        let body: [String: AnyEncodable] = ["caption": AnyEncodable(caption)]
        _ = try await transport.patchSingle(
            path: "candidate_videos",
            query: [("id", "eq.\(videoID)")],
            body: body,
            session: session
        ) as EmptyPayload
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

    /// S-1: reuse / adapt / generate, decided server-side. `matchEssayAnswer`
    /// above stays as the pure-retrieval path — this one supersedes it in the
    /// apply drawer but neither replaces nor removes it.
    func suggestApplicationAnswer(
        question: String,
        jobID: String?,
        charLimit: Int?,
        session: AuthSession
    ) async throws -> AnswerSuggestion {
        var body: [String: AnyEncodable] = ["question": AnyEncodable(question)]
        if let jobID { body["jobId"] = AnyEncodable(jobID) }
        // Only send a limit the form actually declared. `maxlength` is -1 on an
        // unconstrained textarea and 0 would read as "no words allowed".
        if let charLimit, charLimit > 0 { body["charLimit"] = AnyEncodable(charLimit) }

        let request = try transport.makeFunctionRequest(
            name: "suggest-application-answer",
            accessToken: session.accessToken,
            body: body
        )
        return try await transport.execute(request, decode: AnswerSuggestion.self)
    }

    /// S-2: the keyword gap for one job. The job half is cached server-side
    /// after the first candidate opens it, so this is usually one cheap
    /// round trip with no model call at all.
    func fetchKeywordGap(jobID: String, session: AuthSession) async throws -> KeywordGapReport {
        let body: [String: AnyEncodable] = ["jobId": AnyEncodable(jobID)]
        let request = try transport.makeFunctionRequest(
            name: "resume-job-keywords",
            accessToken: session.accessToken,
            body: body
        )
        return try await transport.execute(request, decode: KeywordGapReport.self)
    }

    /// S-3: draft a cover letter for one job. Never cached — a letter names
    /// the company in its opening line, so there is nothing to reuse.
    func generateCoverLetter(jobID: String, session: AuthSession) async throws -> CoverLetterDraft {
        let body: [String: AnyEncodable] = ["jobId": AnyEncodable(jobID)]
        let request = try transport.makeFunctionRequest(
            name: "generate-cover-letter",
            accessToken: session.accessToken,
            body: body
        )
        return try await transport.execute(request, decode: CoverLetterDraft.self)
    }

    /// S-4: rewrite the resume for one posting. The base resume is untouched;
    /// the result is a `resume_versions` row. A refusal for fabrication comes
    /// back as `available: false, reason: "fabrication_detected"` — not an
    /// error, a deliberate decision not to ship that document.
    func tailorResume(
        jobID: String,
        resumeID: String? = nil,
        session: AuthSession
    ) async throws -> TailorResumeResponse {
        var body: [String: AnyEncodable] = ["jobId": AnyEncodable(jobID)]
        if let resumeID { body["resumeId"] = AnyEncodable(resumeID) }
        let request = try transport.makeFunctionRequest(
            name: "tailor-resume",
            accessToken: session.accessToken,
            body: body
        )
        return try await transport.execute(request, decode: TailorResumeResponse.self)
    }

    /// S-4: the candidate's own rewrite of one bullet, filed against the BASE
    /// resume so it carries into every future tailoring rather than living and
    /// dying with one version. Passing empty text clears the override.
    func setBulletOverride(
        resumeID: String,
        bulletKey: String,
        text: String,
        session: AuthSession
    ) async throws {
        let request = try transport.makeRestRequest(
            path: "rpc/set_bullet_override",
            method: "POST",
            accessToken: session.accessToken,
            body: [
                "p_resume_id": AnyEncodable(resumeID),
                "p_bullet_key": AnyEncodable(bulletKey),
                "p_text": AnyEncodable(text)
            ]
        )
        _ = try await transport.executeData(request)
    }

    // MARK: - S-6 application tracking

    /// Upsert the candidate's own view of one application. Separate table
    /// from the employer's pipeline status and from their private notes —
    /// see the migration for why RLS forces that.
    ///
    /// Dates are sent as `nil` to clear, so a candidate can un-set an
    /// interview that got cancelled.
    func updateApplicationTracking(
        applicationID: String,
        candidateID: String,
        stage: CandidateApplicationStage,
        interviewAt: Date?,
        followUpOn: Date?,
        notes: String?,
        session: AuthSession
    ) async throws {
        var row: [String: AnyEncodable] = [
            "application_id": AnyEncodable(applicationID),
            "candidate_profile_id": AnyEncodable(candidateID),
            "stage": AnyEncodable(stage.rawValue),
            "interview_at": AnyEncodable(interviewAt.map(Self.isoFormatter.string(from:))),
            "follow_up_on": AnyEncodable(followUpOn.map(Self.dateOnlyFormatter.string(from:))),
            "updated_at": AnyEncodable(Self.isoFormatter.string(from: Date()))
        ]
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        row["notes"] = AnyEncodable(trimmed?.isEmpty == false ? trimmed : nil)

        let request = try transport.makeRestRequest(
            path: "candidate_application_tracking",
            query: [("on_conflict", "application_id")],
            method: "POST",
            accessToken: session.accessToken,
            body: [row]
        )
        var upsert = request
        // merge-duplicates turns the insert into an upsert; without it a
        // second edit of the same application collides on the primary key.
        upsert.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        _ = try await transport.executeData(upsert)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// `follow_up_on` is a DATE column — sending a timestamp would be coerced
    /// and could land a day off across timezones.
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Tailored versions this candidate holds, newest first.
    func fetchResumeVersions(
        userID: String,
        session: AuthSession
    ) async throws -> [ResumeVersionRecord] {
        try await transport.selectArray(
            path: "resume_versions",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    // Editor-driven corrections to the parsed resume (experience/education/
    // skills shown on the profile). Owner-scoped by RLS.
    func updateResumeParsedDetails(resumeID: String, details: ParsedResumeDetails, session: AuthSession) async throws {
        // Merges rather than replaces. A direct PATCH of parsed_json wrote the
        // four keys ParsedResumeDetails models and dropped everything else the
        // parser had extracted — including, after S-4, the bullets the
        // candidate was about to tailor.
        let request = try transport.makeRestRequest(
            path: "rpc/update_resume_parsed_details",
            method: "POST",
            accessToken: session.accessToken,
            body: [
                "p_resume_id": AnyEncodable(resumeID),
                "p_patch": AnyEncodable(details)
            ]
        )
        _ = try await transport.executeData(request)
    }

    /// S-4: re-parse from the text already on file, no re-upload needed.
    /// Resumes parsed before bullets existed in the schema come back with them.
    func reparseResume(resumeID: String, session: AuthSession) async throws {
        try await invokeParseResume(resumeID: resumeID, rawText: nil, session: session)
    }

    // MARK: - Matching (M-F)

    func fetchJobMatchScores(jobIDs: [String], session: AuthSession) async throws -> [JobMatchScoreRecord] {
        guard !jobIDs.isEmpty else { return [] }
        return try await transport.rpc(
            function: "job_match_scores",
            parameters: ["p_job_ids": AnyEncodable(Array(jobIDs.prefix(500)))],
            session: session
        )
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

    func sendFounderEmail(jobID: String, contactID: String?, note: String?, videoURL: String? = nil, session: AuthSession) async throws -> FounderEmailSendResult {
        let request = try transport.makeFunctionRequest(
            name: "send-founder-email",
            accessToken: session.accessToken,
            body: [
                "jobId": AnyEncodable(jobID),
                "mode": AnyEncodable("send"),
                "contactId": AnyEncodable(contactID),
                "note": AnyEncodable(note?.isEmpty == true ? nil : note),
                "videoUrl": AnyEncodable(videoURL),
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
