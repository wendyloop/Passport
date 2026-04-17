import Foundation
import AuthenticationServices
import UIKit

struct StorageUploadResult {
    let path: String
    let publicURL: String
}

enum SupabaseServiceError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case missingSession
    case oauthCancelled
    case oauthCallbackMissingTokens
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Supabase is not configured in the native app target."
        case .invalidResponse:
            return "Supabase returned an invalid response."
        case .missingSession:
            return "You need to be signed in."
        case .oauthCancelled:
            return "Google sign-in was cancelled."
        case .oauthCallbackMissingTokens:
            return "Google sign-in completed without a valid Supabase session."
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
                "Supabase sign-up succeeded, but no session was returned. Disable email confirmation for now in Supabase Auth if you want immediate in-app access."
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

    @MainActor
    func signInWithGoogle() async throws -> AuthSession {
        try validateConfiguration()

        let redirectURL = "\(config.redirectScheme)://auth-callback"
        var components = URLComponents(url: authBaseURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL),
            URLQueryItem(name: "flow_type", value: "implicit")
        ]

        guard let authorizeURL = components?.url else {
            throw SupabaseServiceError.invalidResponse
        }

        let callbackURL = try await OAuthSessionRunner.run(
            startURL: authorizeURL,
            callbackScheme: config.redirectScheme
        )

        let queryValues = parseCallbackValues(from: callbackURL)

        guard
            let accessToken = queryValues["access_token"],
            let refreshToken = queryValues["refresh_token"]
        else {
            throw SupabaseServiceError.oauthCallbackMissingTokens
        }

        let expiresAt: Date
        if let expiresAtString = queryValues["expires_at"], let epoch = TimeInterval(expiresAtString) {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let expiresInString = queryValues["expires_in"], let seconds = TimeInterval(expiresInString) {
            expiresAt = Date().addingTimeInterval(seconds)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }

        let user = try await fetchCurrentUser(accessToken: accessToken)
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: user
        )
    }

    func fetchCurrentUser(accessToken: String) async throws -> AuthUser {
        try validateConfiguration()

        let request = try makeRequest(
            url: authBaseURL.appendingPathComponent("user"),
            method: "GET",
            accessToken: accessToken
        )

        return try await execute(request, decode: AuthUser.self)
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

    func ensureValidSession(_ session: AuthSession) async throws -> AuthSession {
        if session.expiresAt.timeIntervalSinceNow > 60 {
            return session
        }
        return try await refreshSession(session)
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

    func fetchEmployerProfiles(ids: [String], session: AuthSession) async throws -> [EmployerProfileRecord] {
        guard !ids.isEmpty else { return [] }
        return try await selectArray(
            path: "employer_profiles",
            query: [
                ("profile_id", "in.(\(ids.joined(separator: ",")))"),
                ("select", "*")
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

    func fetchCandidateFeed(session: AuthSession) async throws -> [CandidateFeedRecord] {
        try await selectArray(
            path: "candidate_feed",
            query: [
                ("select", "*"),
                ("order", "full_name.asc")
            ],
            session: session
        )
    }

    func fetchCandidateFeed(candidateIDs: [String], session: AuthSession) async throws -> [CandidateFeedRecord] {
        guard !candidateIDs.isEmpty else { return [] }
        let joined = candidateIDs.joined(separator: ",")
        return try await selectArray(
            path: "candidate_feed",
            query: [
                ("candidate_id", "in.(\(joined))"),
                ("select", "*")
            ],
            session: session
        )
    }

    func fetchCandidateLikes(session: AuthSession) async throws -> [CandidateLikeRecord] {
        try await selectArray(
            path: "candidate_likes",
            query: [
                ("select", "id,candidate_profile_id")
            ],
            session: session
        )
    }

    func fetchAvailabilitySlots(forEmployerID employerID: String? = nil, openOnly: Bool = false, session: AuthSession) async throws -> [AvailabilitySlotRecord] {
        var query: [(String, String)] = [
            ("select", "*"),
            ("order", "start_at.asc")
        ]
        if let employerID {
            query.append(("employer_profile_id", "eq.\(employerID)"))
        }
        if openOnly {
            query.append(("slot_status", "eq.open"))
        }
        return try await selectArray(path: "availability_slots", query: query, session: session)
    }

    func fetchInterviewRequests(for role: UserRole, userID: String, status: String? = nil, session: AuthSession) async throws -> [InterviewRequestRecord] {
        var query: [(String, String)] = [
            ("select", "*"),
            ("order", "requested_at.desc")
        ]
        switch role {
        case .jobSeeker:
            query.append(("candidate_profile_id", "eq.\(userID)"))
        case .employer:
            query.append(("employer_profile_id", "eq.\(userID)"))
        }
        if let status {
            query.append(("status", "eq.\(status)"))
        }

        return try await selectArray(path: "interview_requests", query: query, session: session)
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

    func upsertProfile(
        userID: String,
        email: String?,
        role: UserRole,
        fullName: String,
        headline: String,
        onboardingComplete: Bool,
        session: AuthSession
    ) async throws {
        let body: [[String: AnyEncodable]] = [[
            "id": AnyEncodable(userID),
            "email": AnyEncodable(email),
            "role": AnyEncodable(role.rawValue),
            "full_name": AnyEncodable(fullName),
            "headline": AnyEncodable(headline),
            "onboarding_complete": AnyEncodable(onboardingComplete)
        ]]

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
        introVideoURL: String?,
        session: AuthSession
    ) async throws {
        let body: [[String: AnyEncodable]] = [[
            "profile_id": AnyEncodable(userID),
            "school_name": AnyEncodable(schoolName),
            "job_function": AnyEncodable(jobFunction.rawValue),
            "intro_video_url": AnyEncodable(introVideoURL)
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

    func likeCandidate(candidateID: String, session: AuthSession) async throws {
        let _: String = try await rpc(
            function: "like_candidate",
            parameters: ["p_candidate_profile_id": AnyEncodable(candidateID)],
            session: session
        )
    }

    func selectInterviewSlot(requestID: String, slotID: String, session: AuthSession) async throws {
        let _: String = try await rpc(
            function: "select_interview_slot",
            parameters: [
                "p_request_id": AnyEncodable(requestID),
                "p_slot_id": AnyEncodable(slotID)
            ],
            session: session
        )
    }

    func respondToInterviewRequest(requestID: String, approved: Bool, session: AuthSession) async throws {
        let _: InterviewRequestRecord = try await rpc(
            function: "respond_to_interview_request",
            parameters: [
                "p_request_id": AnyEncodable(requestID),
                "p_approved": AnyEncodable(approved)
            ],
            session: session
        )
    }

    func issueReferralInvite(email: String?, session: AuthSession) async throws -> ReferralInviteRecord {
        try await rpc(
            function: "issue_referral_invite",
            parameters: [
                "p_email": AnyEncodable(email)
            ],
            session: session
        )
    }

    func consumeReferralInvite(token: String, session: AuthSession) async throws {
        let _: ReferralInviteRecord = try await rpc(
            function: "consume_referral_invite",
            parameters: [
                "p_token": AnyEncodable(token)
            ],
            session: session
        )
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

    func addAvailabilitySlot(userID: String, startAt: Date, endAt: Date, session: AuthSession) async throws {
        let body: [[String: AnyEncodable]] = [[
            "employer_profile_id": AnyEncodable(userID),
            "start_at": AnyEncodable(isoString(from: startAt)),
            "end_at": AnyEncodable(isoString(from: endAt)),
            "source": AnyEncodable("manual")
        ]]

        _ = try await postgrestWrite(path: "availability_slots", method: "POST", body: body, session: session) as EmptyPayload
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

    private func validateConfiguration() throws {
        guard !config.isPlaceholderURL, !config.isPlaceholderKey else {
            throw SupabaseServiceError.apiError("Supabase config is still using placeholder values. \(config.debugSummary)")
        }

        guard isConfigured, let url = URL(string: config.supabaseURL), url.host != nil else {
            throw SupabaseServiceError.apiError("Supabase config is invalid. \(config.debugSummary)")
        }
    }

    private var baseURL: URL {
        URL(string: config.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))! 
    }

    private var authBaseURL: URL {
        URL(string: "\(baseURL.absoluteString)/auth/v1")!
    }

    private var restBaseURL: URL {
        URL(string: "\(baseURL.absoluteString)/rest/v1")!
    }

    private var storageBaseURL: URL {
        URL(string: "\(baseURL.absoluteString)/storage/v1")!
    }

    private var functionsBaseURL: URL {
        URL(string: "\(baseURL.absoluteString)/functions/v1")!
    }

    private func restURL(path: String, query: [(String, String)]) -> URL {
        var components = URLComponents(url: restBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url ?? restBaseURL.appendingPathComponent(path)
    }

    private func authURL(path: String, query: [(String, String)]) -> URL {
        var components = URLComponents(url: authBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url ?? authBaseURL.appendingPathComponent(path)
    }

    private func parseCallbackValues(from url: URL) -> [String: String] {
        var values: [String: String] = [:]

        if let fragment = url.fragment {
            fragment
                .split(separator: "&")
                .forEach { pair in
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        values[parts[0]] = parts[1].removingPercentEncoding
                    }
                }
        }

        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach { item in
            values[item.name] = item.value
        }

        return values
    }

    private func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private struct EmptyPayload: Codable { }

private struct SupabaseAPIError: Codable {
    let message: String
}

private struct AuthSessionEnvelope: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    var session: AuthSession? {
        guard let accessToken, let refreshToken, let user else { return nil }
        let resolvedExpiry: Date
        if let expiresAt {
            resolvedExpiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        } else {
            resolvedExpiry = Date().addingTimeInterval(TimeInterval(expiresIn ?? 3600))
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: resolvedExpiry,
            user: user
        )
    }
}

private struct OAuthSessionRunner {
    private static var activeSession: ASWebAuthenticationSession?

    @MainActor
    static func run(startURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    activeSession = nil
                    continuation.resume(throwing: SupabaseServiceError.oauthCancelled)
                    return
                }

                if let error {
                    activeSession = nil
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    activeSession = nil
                    continuation.resume(throwing: SupabaseServiceError.oauthCallbackMissingTokens)
                    return
                }

                activeSession = nil
                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = OAuthPresentationContextProvider.shared
            activeSession = session
            session.start()
        }
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T?) {
        encodeBlock = { encoder in
            var container = encoder.singleValueContainer()
            if let value {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}
