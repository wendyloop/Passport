import Foundation

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

struct StorageUploadResult {
    let path: String
    let publicURL: String
}

struct EmptyPayload: Codable {}

struct SupabaseAPIError: Codable {
    let message: String
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

/// The single place that knows how to talk to Supabase over HTTP: URL
/// construction, headers, encoding/decoding, and error mapping. Domain
/// services (auth, candidate, employer/admin) compose on top of it.
final class SupabaseTransport {
    let config = PassportConfig.load()
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init() {
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

    func validateConfiguration() throws {
        guard isConfigured else {
            throw SupabaseServiceError.invalidConfiguration
        }
    }

    // MARK: - Base URLs (throwing — a malformed SUPABASE_URL surfaces as a
    // configuration error instead of a crash)

    func authBaseURL() throws -> URL {
        try baseURL(suffix: "auth/v1")
    }

    func restBaseURL() throws -> URL {
        try baseURL(suffix: "rest/v1")
    }

    func storageBaseURL() throws -> URL {
        try baseURL(suffix: "storage/v1")
    }

    func functionsBaseURL() throws -> URL {
        try baseURL(suffix: "functions/v1")
    }

    private func baseURL(suffix: String) throws -> URL {
        guard let url = URL(string: "\(config.supabaseURL)/\(suffix)") else {
            throw SupabaseServiceError.invalidConfiguration
        }
        return url
    }

    func restURL(path: String, query: [(String, String)]) throws -> URL {
        let base = try restBaseURL().appendingPathComponent(path)
        return appendQuery(query, to: base)
    }

    func authURL(path: String, query: [(String, String)]) throws -> URL {
        let base = try authBaseURL().appendingPathComponent(path)
        return appendQuery(query, to: base)
    }

    private func appendQuery(_ query: [(String, String)], to url: URL) -> URL {
        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url ?? url
    }

    // MARK: - Request building

    func makeRequest(
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

    func makeRequest<Body: Encodable>(
        url: URL,
        method: String,
        accessToken: String? = nil,
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(url: url, method: method, accessToken: accessToken)
        request.httpBody = try encoder.encode(body)
        return request
    }

    func makeRestRequest(
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

    func makeRestRequest<Body: Encodable>(
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

    func makeFunctionRequest<Body: Encodable>(
        name: String,
        method: String = "POST",
        accessToken: String,
        body: Body
    ) throws -> URLRequest {
        try makeRequest(
            url: functionsBaseURL().appendingPathComponent(name),
            method: method,
            accessToken: accessToken,
            body: body
        )
    }

    // MARK: - Execution

    func execute<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
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
            let path = request.url?.path ?? "?"
            let preview = String(data: data.prefix(1500), encoding: .utf8) ?? "<non-utf8>"
            AppLog.network.error("Decode failed for \(String(describing: T.self)) at \(path): \(String(describing: error)); raw: \(preview)")
            throw error
        }
    }

    func executeData(_ request: URLRequest) async throws -> Data {
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

    // MARK: - PostgREST verbs

    func selectArray<T: Decodable>(
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

    func selectSingle<T: Decodable>(
        path: String,
        query: [(String, String)],
        session: AuthSession
    ) async throws -> T? {
        let items: [T] = try await selectArray(path: path, query: query, session: session)
        return items.first
    }

    func postgrestWrite<T: Decodable, Body: Encodable>(
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

    func patchSingle<T: Decodable, Body: Encodable>(
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

    func rpc<T: Decodable>(
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

    func delete(path: String, query: [(String, String)], session: AuthSession) async throws {
        let request = try makeRestRequest(
            path: path,
            query: query,
            method: "DELETE",
            accessToken: session.accessToken
        )
        _ = try await executeData(request)
    }

    // MARK: - Storage

    func encodeStoragePath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
    }
}
