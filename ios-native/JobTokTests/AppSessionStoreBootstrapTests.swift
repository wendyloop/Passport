import XCTest
@testable import JobTok

// AUDIT P0-1: bootstrap must distinguish "network unreachable" (keep the
// persisted session, retry later) from "refresh token rejected" (sign out).
// AUDIT P1-1: persistence goes through the SessionPersisting seam (Keychain
// in production, in-memory here).
@MainActor
final class AppSessionStoreBootstrapTests: XCTestCase {
    private var persistence: InMemorySessionPersistence!

    override func setUp() {
        super.setUp()
        persistence = InMemorySessionPersistence()
    }

    override func tearDown() {
        RefreshEndpointStub.handler = nil
        URLProtocol.unregisterClass(RefreshEndpointStub.self)
        super.tearDown()
    }

    private func makeSession() -> AuthSession {
        AuthSession(
            accessToken: "expired-access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: -3600),
            user: AuthUser(id: "user-1", email: "test@example.com")
        )
    }

    private func persistSession() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        persistence.stored = try encoder.encode(makeSession())
    }

    private func makeStore(failingWith error: Error) -> AppSessionStore {
        AppSessionStore(
            sessionValidator: StubSessionValidator(error: error),
            sessionPersistence: persistence,
            sharedDefaults: nil,
            bootstrapsOnInit: false,
            connectivityRetryEnabled: false
        )
    }

    // Airplane-mode launch: the session survives and the app waits to retry.
    func testOfflineBootstrapKeepsSessionAndEntersOfflinePhase() async throws {
        try persistSession()
        let store = makeStore(failingWith: URLError(.notConnectedToInternet))

        await store.bootstrap()

        XCTAssertEqual(store.phase, .offline)
        XCTAssertNotNil(store.session)
        XCTAssertNotNil(
            persistence.stored,
            "an offline launch must not destroy the persisted session"
        )
    }

    // A server hiccup (5xx) is not an auth rejection either.
    func testServerErrorBootstrapKeepsSession() async throws {
        try persistSession()
        let store = makeStore(
            failingWith: SupabaseServiceError.httpError(statusCode: 503, message: "upstream unavailable")
        )

        await store.bootstrap()

        XCTAssertEqual(store.phase, .offline)
        XCTAssertNotNil(store.session)
        XCTAssertNotNil(persistence.stored)
    }

    // A definitive refresh rejection still signs the user out.
    func testRejectedRefreshTokenClearsSessionAndSignsOut() async throws {
        try persistSession()
        let store = makeStore(failingWith: AuthServiceError.refreshRejected("Invalid Refresh Token"))

        await store.bootstrap()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(
            persistence.stored,
            "a rejected refresh token must clear the persisted session"
        )
    }

    // No persisted session at all: straight to the sign-in screen.
    func testBootstrapWithoutPersistedSessionSignsOut() async {
        let store = makeStore(failingWith: URLError(.notConnectedToInternet))

        await store.bootstrap()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
    }

    // End-to-end mapping: a real HTTP 400 from the refresh endpoint becomes
    // AuthServiceError.refreshRejected (the sign-out signal)…
    func testRefreshSessionMapsHTTP400ToRefreshRejected() async throws {
        URLProtocol.registerClass(RefreshEndpointStub.self)
        RefreshEndpointStub.handler = { _ in
            .success((400, Data(#"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#.utf8)))
        }

        let authService = AuthService(transport: SupabaseTransport())
        do {
            _ = try await authService.refreshSession(makeSession())
            XCTFail("Expected refreshSession to throw")
        } catch is AuthServiceError {
            // Expected: definitive rejection.
        } catch {
            XCTFail("Expected AuthServiceError.refreshRejected, got \(error)")
        }
    }

    // …while a transport-level failure surfaces as-is, so bootstrap retries.
    func testRefreshSessionPassesThroughNetworkErrors() async throws {
        URLProtocol.registerClass(RefreshEndpointStub.self)
        RefreshEndpointStub.handler = { _ in
            .failure(URLError(.notConnectedToInternet))
        }

        let authService = AuthService(transport: SupabaseTransport())
        do {
            _ = try await authService.refreshSession(makeSession())
            XCTFail("Expected refreshSession to throw")
        } catch is AuthServiceError {
            XCTFail("A network failure must not be treated as an auth rejection")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
        }
    }
}

// AUDIT P1-1: the real Keychain store round-trips in the hosted app (the
// host holds the App Group entitlement the access group needs).
final class KeychainStoreTests: XCTestCase {
    override func tearDown() {
        KeychainStore.delete()
        super.tearDown()
    }

    func testSaveLoadDeleteRoundTrip() throws {
        let payload = Data(#"{"accessToken":"kc-test"}"#.utf8)
        try KeychainStore.save(payload)
        XCTAssertEqual(KeychainStore.load(), payload)

        let replacement = Data(#"{"accessToken":"kc-test-2"}"#.utf8)
        try KeychainStore.save(replacement)
        XCTAssertEqual(KeychainStore.load(), replacement, "save must overwrite, not duplicate")

        KeychainStore.delete()
        XCTAssertNil(KeychainStore.load())
    }
}

private struct StubSessionValidator: SessionValidating {
    let error: Error

    func ensureValidSession(_ session: AuthSession) async throws -> AuthSession {
        throw error
    }
}

private final class InMemorySessionPersistence: SessionPersisting {
    var stored: Data?

    func save(_ data: Data) throws { stored = data }
    func load() -> Data? { stored }
    func clear() { stored = nil }
}

/// Intercepts only the Supabase auth token endpoint on the shared URLSession.
private final class RefreshEndpointStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool {
        guard handler != nil else { return false }
        return request.url?.path.contains("/auth/v1/token") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch handler(request) {
        case .success(let (statusCode, body)):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
