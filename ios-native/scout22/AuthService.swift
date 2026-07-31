import Foundation

enum SocialAuthProvider: String {
    case google
    case apple
}

/// A definitive rejection of the refresh token by the auth server (revoked,
/// reused, or malformed) — as opposed to a network or server failure. This is
/// the only error that should destroy a persisted session (AUDIT P0-1).
enum AuthServiceError: LocalizedError {
    case refreshRejected(String)

    var errorDescription: String? {
        switch self {
        case .refreshRejected:
            return "Your session has expired. Please sign in again."
        }
    }
}

/// The slice of AuthService that session bootstrap depends on — injectable so
/// tests can simulate network-unreachable vs auth-rejected refresh outcomes.
protocol SessionValidating {
    func ensureValidSession(_ session: AuthSession) async throws -> AuthSession
}

/// Supabase Auth: password + OAuth sign-in, session refresh, sign-out.
final class AuthService {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try transport.validateConfiguration()
        let request = try transport.makeRequest(
            url: transport.authURL(path: "signup", query: []),
            method: "POST",
            body: [
                "email": email,
                "password": password
            ]
        )
        let envelope = try await transport.execute(request, decode: AuthSessionEnvelope.self)

        guard let session = envelope.session else {
            throw SupabaseServiceError.apiError(
                "Supabase sign-up succeeded, but no session was returned. Disable email confirmation in Supabase Auth if you want immediate access in the app."
            )
        }

        return session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try transport.validateConfiguration()
        let request = try transport.makeRequest(
            url: transport.authURL(path: "token", query: [("grant_type", "password")]),
            method: "POST",
            body: [
                "email": email,
                "password": password
            ]
        )
        let envelope = try await transport.execute(request, decode: AuthSessionEnvelope.self)
        guard let session = envelope.session else {
            throw SupabaseServiceError.invalidResponse
        }
        return session
    }

    func oauthAuthorizationURL(provider: SocialAuthProvider, redirectTo: URL) throws -> URL {
        try transport.validateConfiguration()
        return try transport.authURL(
            path: "authorize",
            query: [
                ("provider", provider.rawValue),
                ("redirect_to", redirectTo.absoluteString)
            ]
        )
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
        try transport.validateConfiguration()
        let request = try transport.makeRequest(
            url: transport.authURL(path: "token", query: [("grant_type", "refresh_token")]),
            method: "POST",
            body: [
                "refresh_token": session.refreshToken
            ]
        )
        let envelope: AuthSessionEnvelope
        do {
            envelope = try await transport.execute(request, decode: AuthSessionEnvelope.self)
        } catch SupabaseServiceError.httpError(let statusCode, let message) where [400, 401, 403].contains(statusCode) {
            // The server saw the request and rejected the token; anything
            // else (URLError, 5xx) is treated as retryable by callers.
            throw AuthServiceError.refreshRejected(message)
        }
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
        guard transport.isConfigured else { return }
        do {
            let request = try transport.makeRequest(
                url: transport.authBaseURL().appendingPathComponent("logout"),
                method: "POST",
                accessToken: session.accessToken,
                body: ["scope": "global"]
            )
            _ = try await transport.executeData(request)
        } catch {
            // Best effort only.
        }
    }

    // MARK: - Private

    private func fetchAuthUser(accessToken: String) async throws -> AuthUser {
        let request = try transport.makeRequest(
            url: transport.authBaseURL().appendingPathComponent("user"),
            method: "GET",
            accessToken: accessToken
        )
        return try await transport.execute(request, decode: AuthUser.self)
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
}

extension AuthService: SessionValidating {}

struct AuthSessionEnvelope: Codable {
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
