import XCTest
@testable import Psst

/// Answers every request with one canned auth reply.
private final class StubAuthProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 400
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MemorySessionStore: SessionStore {
    var saved: AuthSession?
    init(_ session: AuthSession?) { saved = session }
    func load() -> AuthSession? { saved }
    func save(_ session: AuthSession?) { saved = session }
}

/// 1.0.9 audit: a refresh token that was already used (the widget rotated it, or a
/// refresh was cut off) keeps the account; a session the server says is gone ends it.
@MainActor
final class SessionRefreshTests: XCTestCase {
    private let expired = AuthSession(accessToken: "a", refreshToken: "r1", userID: UUID(),
                                      expiresAt: Date(timeIntervalSinceNow: -10))

    private func client(_ store: MemorySessionStore, status: Int, body: String) -> APIClient {
        StubAuthProtocol.status = status
        StubAuthProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAuthProtocol.self]
        return APIClient(config: AppConfig(baseURL: URL(string: "https://example.invalid")!, anonKey: "anon"),
                         urlSession: URLSession(configuration: configuration), store: store)
    }

    func testAnAlreadyUsedRefreshTokenKeepsTheAccount() async {
        let store = MemorySessionStore(expired)
        let api = client(store, status: 400,
                         body: #"{"code":400,"error_code":"refresh_token_already_used","msg":"Invalid Refresh Token: Already Used"}"#)
        do {
            _ = try await api.listConnections()
            XCTFail("the refresh failed")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        XCTAssertTrue(api.isSignedIn)
        XCTAssertEqual(store.saved, expired)
    }

    func testAGoneSessionStillSignsOut() async {
        let store = MemorySessionStore(expired)
        let api = client(store, status: 400,
                         body: #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token: Refresh Token Not Found"}"#)
        do {
            _ = try await api.listConnections()
            XCTFail("the refresh failed")
        } catch {
            XCTAssertEqual(error as? APIError, .signedOut)
        }
        XCTAssertFalse(api.isSignedIn)
        XCTAssertNil(store.saved)
    }

    /// Older Auth servers only say "invalid_grant"; the description tells the two apart.
    func testOlderAuthErrorsAreToldApart() {
        let used = #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#
        let gone = #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Refresh Token Not Found"}"#
        XCTAssertEqual(APIClient.errorCode(from: Data(used.utf8)), "refresh_token_already_used")
        XCTAssertEqual(APIClient.errorCode(from: Data(gone.utf8)), "invalid_grant")
    }

    /// Before the first unlock nothing could be read; afterwards the saved session is found.
    func testASessionSavedBeforeLaunchIsFoundLater() {
        let store = MemorySessionStore(nil)
        let api = client(store, status: 200, body: "[]")
        XCTAssertFalse(api.isSignedIn)
        store.saved = expired
        api.reloadSession()
        XCTAssertTrue(api.isSignedIn)
        XCTAssertEqual(api.accountID, expired.userID)
    }
}
