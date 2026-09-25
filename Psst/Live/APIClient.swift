import Foundation

enum APIError: Error, Equatable {
    /// No connection, timeout or similar: nothing reached the server.
    case offline
    /// The server answered with an error code such as "not_connected".
    case server(status: Int, code: String)
    case signedOut
    case invalidResponse
}

/// Everything the app asks of the backend. Main-actor isolated: callers are UI state.
@MainActor
protocol PsstAPI: AnyObject {
    var isSignedIn: Bool { get }
    func signUpAnonymously() async throws
    func setDisplayName(_ name: String) async throws
    func listConnections() async throws -> [ConnectionSummary]
    func listUnseen() async throws -> [UnseenSignal]
    func ackSignals(_ ids: [UUID]) async throws
    func sendSignal(eventID: UUID, connectionID: UUID, signal: Signal) async throws -> SendResult
    func createInvite() async throws -> CreatedInvite
    func previewInvite(code: String) async throws -> InvitePreview
    func acceptInvite(code: String) async throws -> AcceptedInvite
    func removeConnection(_ id: UUID) async throws
    func blockUser(_ id: UUID) async throws
    func unblockUser(_ id: UUID) async throws
    func reportUser(_ id: UUID) async throws
    func listBlocked() async throws -> [BlockedPerson]
    func listOpenInvites() async throws -> [OpenInvite]
    func revokeInvite(code: String) async throws
    func setNotificationSound(_ file: String) async throws
    func setNotificationStatus(_ enabled: Bool) async throws
    func registerDeviceToken(_ token: String, environment: String) async throws
    func deleteAccount() async throws
    func signOutLocally()
}

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userID: UUID
    var expiresAt: Date
}

/// Supabase Auth, PostgREST and Edge Functions over URLSession.
@MainActor
final class APIClient: PsstAPI {
    private let config: AppConfig
    private let urlSession: URLSession
    private let store: SessionStore
    private var session: AuthSession?

    init(config: AppConfig, urlSession: URLSession = .shared, store: SessionStore = KeychainSessionStore()) {
        self.config = config
        self.urlSession = urlSession
        self.store = store
        self.session = store.load()
    }

    var isSignedIn: Bool { session != nil }

    // MARK: Auth

    private struct AuthResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User

        var session: AuthSession {
            AuthSession(accessToken: accessToken, refreshToken: refreshToken, userID: user.id,
                        expiresAt: Date().addingTimeInterval(expiresIn))
        }
    }

    func signUpAnonymously() async throws {
        let response: AuthResponse = try await request(
            path: "auth/v1/signup", body: ["data": [String: String]()], authorized: false)
        setSession(response.session)
    }

    private func refreshIfNeeded(force: Bool = false) async throws -> AuthSession {
        guard let current = session else { throw APIError.signedOut }
        guard force || current.expiresAt.timeIntervalSinceNow < 60 else { return current }
        do {
            let response: AuthResponse = try await request(
                path: "auth/v1/token?grant_type=refresh_token",
                body: ["refresh_token": current.refreshToken], authorized: false)
            setSession(response.session)
            return response.session
        } catch APIError.server(let status, _) where (400..<500).contains(status) {
            signOutLocally()
            throw APIError.signedOut
        }
    }

    private func setSession(_ new: AuthSession?) {
        session = new
        store.save(new)
    }

    func signOutLocally() {
        setSession(nil)
    }

    // MARK: Calls

    func setDisplayName(_ name: String) async throws {
        try await rpcVoid("set_display_name", ["p_name": name])
    }

    func listConnections() async throws -> [ConnectionSummary] {
        try await rpc("list_connections", [String: String]())
    }

    func listUnseen() async throws -> [UnseenSignal] {
        try await rpc("list_unseen", [String: String]())
    }

    func ackSignals(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let _: Int = try await rpc("ack_signals", ["p_event_ids": ids])
    }

    func sendSignal(eventID: UUID, connectionID: UUID, signal: Signal) async throws -> SendResult {
        try await authorizedRequest(path: "functions/v1/send-signal", body: [
            "event_id": eventID.uuidString.lowercased(),
            "connection_id": connectionID.uuidString.lowercased(),
            "effect_id": signal.rawValue,
        ])
    }

    func createInvite() async throws -> CreatedInvite {
        try await rpc("create_invite", [String: String]())
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        try await rpc("preview_invite", ["p_code": code])
    }

    func acceptInvite(code: String) async throws -> AcceptedInvite {
        try await rpc("accept_invite", ["p_code": code])
    }

    func removeConnection(_ id: UUID) async throws {
        try await rpcVoid("remove_connection", ["p_connection_id": id.uuidString])
    }

    func blockUser(_ id: UUID) async throws {
        try await rpcVoid("block_user", ["p_user_id": id.uuidString])
    }

    func reportUser(_ id: UUID) async throws {
        try await rpcVoid("report_user", ["p_user_id": id.uuidString])
    }

    func unblockUser(_ id: UUID) async throws {
        try await rpcVoid("unblock_user", ["p_user_id": id.uuidString])
    }

    func listBlocked() async throws -> [BlockedPerson] {
        try await rpc("list_blocked", [String: String]())
    }

    func listOpenInvites() async throws -> [OpenInvite] {
        try await rpc("list_open_invites", [String: String]())
    }

    func revokeInvite(code: String) async throws {
        try await rpcVoid("revoke_invite", ["p_code": code])
    }

    func setNotificationSound(_ file: String) async throws {
        try await rpcVoid("set_notification_sound", ["p_sound": file])
    }

    func setNotificationStatus(_ enabled: Bool) async throws {
        try await rpcVoid("set_notification_status", ["p_enabled": enabled])
    }

    func registerDeviceToken(_ token: String, environment: String) async throws {
        try await rpcVoid("register_device_token", ["p_token": token, "p_environment": environment])
    }

    func deleteAccount() async throws {
        let _: EmptyResponse = try await authorizedRequest(path: "functions/v1/delete-account", body: [String: String]())
        signOutLocally()
    }

    // MARK: Plumbing

    private struct EmptyResponse: Decodable {}

    private func rpc<Params: Encodable, Response: Decodable>(_ name: String, _ params: Params) async throws -> Response {
        try await authorizedRequest(path: "rest/v1/rpc/\(name)", body: params)
    }

    private func rpcVoid<Params: Encodable>(_ name: String, _ params: Params) async throws {
        let _: EmptyResponse = try await authorizedRequest(path: "rest/v1/rpc/\(name)", body: params)
    }

    private func authorizedRequest<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        do {
            return try await request(path: path, body: body, authorized: true)
        } catch APIError.server(401, _) {
            // The access token may have been revoked or expired early: refresh once.
            _ = try await refreshIfNeeded(force: true)
            return try await request(path: path, body: body, authorized: true)
        }
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String, body: Body, authorized: Bool
    ) async throws -> Response {
        var request = URLRequest(url: URL(string: path, relativeTo: config.baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if authorized {
            let current = try await refreshIfNeeded()
            request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, code: Self.errorCode(from: data))
        }
        if data.isEmpty || http.statusCode == 204, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            if let empty = EmptyResponse() as? Response { return empty }
            throw APIError.invalidResponse
        }
    }

    /// PostgREST errors carry the code in "message"; functions use "error"; auth uses "error_code".
    nonisolated static func errorCode(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "unknown" }
        for key in ["error_code", "error", "message", "msg"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return "unknown"
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseTimestamp(string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognized date \(string)"))
        }
        return decoder
    }()

    /// Postgres timestamps: "2026-09-24T06:10:12.123456+00:00", with 0–6 fractional digits.
    nonisolated static func parseTimestamp(_ string: String) -> Date? {
        var normalized = string.replacingOccurrences(of: " ", with: "T")
        if let dot = normalized.firstIndex(of: ".") {
            let fractionStart = normalized.index(after: dot)
            let fractionEnd = normalized[fractionStart...].firstIndex { !$0.isNumber } ?? normalized.endIndex
            var digits = String(normalized[fractionStart..<fractionEnd])
            digits = String((digits + "000").prefix(3))
            normalized.replaceSubrange(fractionStart..<fractionEnd, with: digits)
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: normalized) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: normalized)
    }
}

// MARK: Session storage

protocol SessionStore {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

/// Stored so notification actions can use it after first unlock; never synced off the device.
struct KeychainSessionStore: SessionStore {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.psst.session",
        kSecAttrAccount as String: "session",
    ]

    func load() -> AuthSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
