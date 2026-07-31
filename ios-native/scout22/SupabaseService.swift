import Foundation

/// Shared + employer/admin backend calls. Auth lives in AuthService and the
/// candidate domain in CandidateService; all three share one transport.
// TODO(deferred): Full DI. Services are reached via SupabaseService.shared;
// only ApplyDrawerView/FounderEmailSheet take an injected CandidateService.
// Protocol-extract each service and inject through the view tree so they're
// mockable in tests. Big diff for a test-only payoff today — revisit when
// service-level (networking) tests are wanted. See docs/DEFERRED_WORK.md.
final class SupabaseService {
    static let shared = SupabaseService()

    let transport: SupabaseTransport
    let auth: AuthService
    let candidate: CandidateService

    private init() {
        transport = SupabaseTransport()
        auth = AuthService(transport: transport)
        candidate = CandidateService(transport: transport)
    }

    var isConfigured: Bool {
        transport.isConfigured
    }

    // MARK: - Profiles (shared)

    func fetchProfile(userID: String, session: AuthSession) async throws -> AppProfileRecord? {
        try await transport.selectSingle(
            path: "profiles",
            query: [
                ("id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchProfiles(ids: [String], session: AuthSession) async throws -> [AppProfileRecord] {
        guard !ids.isEmpty else { return [] }
        return try await transport.selectArray(
            path: "profiles",
            query: [
                ("id", "in.(\(ids.joined(separator: ",")))"),
                ("select", "id,role,full_name,email,headline,onboarding_complete")
            ],
            session: session
        )
    }

    func setOnboardingComplete(userID: String, session: AuthSession) async throws {
        let body: [String: AnyEncodable] = ["onboarding_complete": AnyEncodable(true)]
        _ = try await transport.patchSingle(
            path: "profiles",
            query: [("id", "eq.\(userID)")],
            body: body,
            session: session
        ) as EmptyPayload
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

        _ = try await transport.postgrestWrite(
            path: "profiles",
            method: "POST",
            query: [("on_conflict", "id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    func deleteAccount(session: AuthSession) async throws {
        let request = try transport.makeFunctionRequest(
            name: "delete-account",
            accessToken: session.accessToken,
            body: [:] as [String: String]
        )
        _ = try await transport.executeData(request)
    }

    // MARK: - Employer profiles

    func fetchEmployerProfile(userID: String, session: AuthSession) async throws -> EmployerProfileRecord? {
        try await transport.selectSingle(
            path: "employer_profiles",
            query: [
                ("profile_id", "eq.\(userID)"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchEmployerProfiles(session: AuthSession) async throws -> [EmployerProfileRecord] {
        try await transport.selectArray(
            path: "employer_profiles",
            query: [
                ("select", "*"),
                ("order", "company_name.asc")
            ],
            session: session
        )
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

        _ = try await transport.postgrestWrite(
            path: "employer_profiles",
            method: "POST",
            query: [("on_conflict", "profile_id")],
            body: body,
            session: session,
            prefer: "resolution=merge-duplicates"
        ) as EmptyPayload
    }

    // MARK: - Notifications

    func fetchNotifications(session: AuthSession) async throws -> [NotificationRecord] {
        try await transport.selectArray(
            path: "notifications",
            query: [
                ("select", "id,title,body,created_at,read_at"),
                ("order", "created_at.desc")
            ],
            session: session
        )
    }

    func markNotificationsRead(ids: [String]?, session: AuthSession) async throws {
        let payload = ids.map { ids in ids.map(AnyEncodable.init) }
        let _: Int = try await transport.rpc(
            function: "mark_notifications_read",
            parameters: [
                "p_notification_ids": AnyEncodable(payload)
            ],
            session: session
        )
    }

    // MARK: - Jobs (shared: candidate feed + employer/admin management)

    func fetchJobs(
        publishedOnly: Bool = false,
        employerID: String? = nil,
        filters: FeedFilters = FeedFilters(),
        session: AuthSession
    ) async throws -> [JobPostingRecord] {
        // The candidate feed (publishedOnly) splits into two queries so we never
        // fetch board/ATS rows that have no carousel — otherwise the 32k+ newly
        // ingested board rows would crowd out the older reels under PostgREST's
        // default row cap. Reels/employer posts come back regardless; board/ATS
        // come back only with an `!inner` join on a generated carousel.
        //
        // Filters run server-side: the fetch window is 200+200 rows of a 33k
        // catalog, so client-only filtering would miss nearly all matches.
        if publishedOnly && employerID == nil {
            var filterParams = filters.postgrestParams
            // Founder-reachable and company-size filter on the embedded
            // company — PostgREST only allows that through an !inner join,
            // so the company embed flips to inner and gains the conditions.
            let companyFiltered = filters.founderReachable || filters.companySize != .all
            let companyEmbed = companyFiltered
                ? "company:companies!inner(id,name,domain,logo_url,stage,founder_contactable,size_bucket)"
                : "company:companies(id,name,domain,logo_url,stage,founder_contactable,size_bucket)"
            if filters.founderReachable {
                filterParams.append(("company.founder_contactable", "eq.true"))
            }
            if let bucket = filters.companySize.bucketValue {
                filterParams.append(("company.size_bucket", "eq.\(bucket)"))
            }
            async let videos: [JobPostingRecord] = transport.selectArray(
                path: "jobs",
                query: [
                    ("select", "*,\(companyEmbed),carousel:carousels(theme_id,slide_count,content,status)"),
                    ("is_published", "eq.true"),
                    ("is_active", "eq.true"),
                    ("source_kind", "in.(reel,employer_post)"),
                    ("order", "created_at.desc"),
                    ("limit", "200")
                ] + filterParams,
                session: session
            )
            async let carousels: [JobPostingRecord] = transport.selectArray(
                path: "jobs",
                query: [
                    ("select", "*,\(companyEmbed),carousel:carousels!inner(theme_id,slide_count,content,status)"),
                    ("is_published", "eq.true"),
                    ("is_active", "eq.true"),
                    ("source_kind", "in.(ats,board)"),
                    ("carousel.status", "eq.generated"),
                    ("order", "created_at.desc"),
                    ("limit", "200")
                ] + filterParams,
                session: session
            )
            let merged = try await videos + carousels
            // Feed ranking tiers, most important first:
            //  1. FIRST-100-USERS founder-fatigue: founder reached today →
            //     bottom; this week → slightly less demoted. Spreads early
            //     applications across companies; revisit at volume
            //     (migration 20260708140000).
            //  2. F8 big-company demotion: 1000+/acquired/IPO rank below
            //     startups — the product promise is startup jobs.
            //  3. F6 For-You affinity (applied post-fetch by the store,
            //     where saves/applies are known — see JobPostingRecord.feedRank).
            //  4. F3 comp transparency: salary-listed jobs first (they
            //     convert 30-44% better per LinkedIn/SHRM research).
            //  5. Freshness.
            let now = Date()
            return merged.sorted { a, b in
                let ra = a.feedRank(now: now, affinity: [])
                let rb = b.feedRank(now: now, affinity: [])
                if ra != rb { return ra < rb }
                return a.createdAt > b.createdAt
            }
        }

        var query: [(String, String)] = [
            ("select", "*,company:companies(id,name,domain,logo_url,stage,founder_contactable,size_bucket),carousel:carousels(theme_id,slide_count,content,status)"),
            ("order", "created_at.desc")
        ]
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        return try await transport.selectArray(path: "jobs", query: query, session: session)
    }

    /// Resolves specific jobs by id — used by the Saved tab so bookmarks that
    /// fell out of the 200+200 feed window still render. Chunked to keep the
    /// `id=in.(…)` query string within sane URL length.
    func fetchJobs(ids: [String], session: AuthSession) async throws -> [JobPostingRecord] {
        var results: [JobPostingRecord] = []
        var remaining = ids[...]
        while !remaining.isEmpty {
            let chunk = remaining.prefix(50)
            remaining = remaining.dropFirst(50)
            let rows: [JobPostingRecord] = try await transport.selectArray(
                path: "jobs",
                query: [
                    ("select", "*,company:companies(id,name,domain,logo_url,stage,founder_contactable,size_bucket),carousel:carousels(theme_id,slide_count,content,status)"),
                    ("id", "in.(\(chunk.joined(separator: ",")))")
                ],
                session: session
            )
            results.append(contentsOf: rows)
        }
        return results
    }

    func fetchJobApplications(candidateID: String? = nil, employerID: String? = nil, session: AuthSession) async throws -> [JobApplicationRecord] {
        // Employers also get their private notes (employer-only table, RLS
        // keeps the embed empty for anyone else — AUDIT P1-9).
        var query: [(String, String)] = [
            ("select", employerID != nil ? "*,application_notes(notes)" : "*"),
            ("order", "applied_at.desc")
        ]
        if let candidateID {
            query.append(("candidate_profile_id", "eq.\(candidateID)"))
        }
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        return try await transport.selectArray(path: "job_applications", query: query, session: session)
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

        _ = try await transport.postgrestWrite(path: "jobs", method: "POST", body: body, session: session, prefer: "return=minimal") as EmptyPayload
    }

    func updateJobPublishState(jobID: String, isPublished: Bool, session: AuthSession) async throws {
        let body: [String: AnyEncodable] = [
            "is_published": AnyEncodable(isPublished)
        ]
        let _: EmptyPayload = try await transport.patchSingle(
            path: "jobs",
            query: [("id", "eq.\(jobID)")],
            body: body,
            session: session
        )
    }

    func parseSharedJobPosting(sourceURL: String, session: AuthSession) async throws -> ImportedJobSuggestion {
        let request = try transport.makeFunctionRequest(
            name: "parse-shared-job-posting",
            accessToken: session.accessToken,
            body: ["sourceURL": AnyEncodable(sourceURL)]
        )
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let envelope = try transport.decoder.decode(ImportedJobSuggestionEnvelope.self, from: data)
            return envelope.suggestion
        } catch let decodeError {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 data>"
            throw SupabaseServiceError.apiError("HTTP \(statusCode)\n\nDecode error: \(decodeError.localizedDescription)\n\nRaw response:\n\(rawBody.prefix(2000))")
        }
    }

    // MARK: - Employer application workflow (P1 + P2)

    func updateApplication(
        applicationID: String,
        status: String? = nil,
        internalNotes: String? = nil,
        session: AuthSession
    ) async throws {
        if let status {
            let body: [String: AnyEncodable] = ["status": AnyEncodable(status)]
            let _: EmptyPayload = try await transport.patchSingle(
                path: "job_applications",
                query: [("id", "eq.\(applicationID)")],
                body: body,
                session: session
            )
        }
        if let internalNotes {
            // AUDIT P1-9: notes go to the employer-only application_notes
            // table, never onto the candidate-readable application row.
            let body: [String: AnyEncodable] = [
                "application_id": AnyEncodable(applicationID),
                "employer_profile_id": AnyEncodable(session.user.id),
                "notes": AnyEncodable(internalNotes)
            ]
            _ = try await transport.postgrestWrite(
                path: "application_notes",
                method: "POST",
                query: [("on_conflict", "application_id")],
                body: body,
                session: session,
                prefer: "resolution=merge-duplicates,return=minimal"
            ) as EmptyPayload
        }
    }

    func resumeDownloadURL(applicationID: String, session: AuthSession) async throws -> URL {
        let request = try transport.makeFunctionRequest(
            name: "get-resume-url",
            accessToken: session.accessToken,
            body: ["applicationId": AnyEncodable(applicationID)]
        )
        struct Envelope: Codable { let url: String }
        let envelope = try await transport.execute(request, decode: Envelope.self)
        guard let url = URL(string: envelope.url) else {
            throw SupabaseServiceError.invalidResponse
        }
        return url
    }

    // MARK: - Employer discovery + outreach

    func fetchDiscoverableCandidates(session: AuthSession) async throws -> [DiscoverableCandidateRecord] {
        try await transport.selectArray(
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
        return try await transport.selectArray(path: "candidate_outreach_messages", query: query, session: session)
    }

    func reachOutToCandidate(
        candidateID: String,
        relatedJobID: String?,
        subject: String,
        message: String,
        session: AuthSession
    ) async throws -> CandidateOutreachRecord {
        let request = try transport.makeFunctionRequest(
            name: "reach-out-to-candidate",
            accessToken: session.accessToken,
            body: [
                "candidateId": AnyEncodable(candidateID),
                "relatedJobId": AnyEncodable(relatedJobID),
                "subject": AnyEncodable(subject),
                "message": AnyEncodable(message)
            ]
        )
        let response = try await transport.execute(request, decode: CandidateOutreachEnvelope.self)
        return response.outreach
    }

    // MARK: - Storage (shared: avatars, job videos, resumes)

    func uploadFile(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        session: AuthSession,
        upsert: Bool = true
    ) async throws -> StorageUploadResult {
        let encodedPath = transport.encodeStoragePath(path)
        let storageBase = try transport.storageBaseURL()

        guard let uploadURL = URL(string: "\(storageBase.absoluteString)/object/\(bucket)/\(encodedPath)") else {
            throw SupabaseServiceError.invalidConfiguration
        }
        var request = try transport.makeRequest(
            url: uploadURL,
            method: "POST",
            accessToken: session.accessToken
        )
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(upsert ? "true" : "false", forHTTPHeaderField: "x-upsert")

        _ = try await transport.executeData(request)

        let publicURL = storageBase
            .appendingPathComponent("object/public/\(bucket)/\(encodedPath)")
            .absoluteString

        return StorageUploadResult(path: path, publicURL: publicURL)
    }

    func createSignedFileURL(
        bucket: String,
        path: String,
        expiresIn: Int,
        session: AuthSession
    ) async throws -> URL {
        let encodedPath = transport.encodeStoragePath(path)
        let storageBase = try transport.storageBaseURL()

        guard let signURL = URL(string: "\(storageBase.absoluteString)/object/sign/\(bucket)/\(encodedPath)") else {
            throw SupabaseServiceError.invalidConfiguration
        }
        let request = try transport.makeRequest(
            url: signURL,
            method: "POST",
            accessToken: session.accessToken,
            body: ["expiresIn": AnyEncodable(expiresIn)]
        )
        let response = try await transport.execute(request, decode: StorageSignedURLEnvelope.self)
        if let absolute = URL(string: response.signedURL), absolute.scheme != nil {
            return absolute
        }
        let normalized = response.signedURL.hasPrefix("/") ? String(response.signedURL.dropFirst()) : response.signedURL
        return storageBase.appendingPathComponent(normalized)
    }

    // MARK: - Generic

    func delete(path: String, query: [(String, String)], session: AuthSession) async throws {
        try await transport.delete(path: path, query: query, session: session)
    }
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
