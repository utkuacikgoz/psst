import AppIntents
import Foundation
import Security
import SwiftUI
import WidgetKit

// 2A (owner pick, 15 Oct 2026): a Control Center / Lock Screen button that sends a
// Psst to the person you chose, without opening the app. iOS 18 and later.

/// Someone you can psst, from the list the app shares (WidgetBridge.everyoneKey).
struct PsstPersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PsstPersonQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static func everyone() -> [PsstPersonEntity] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PSSTAppGroup") as? String,
              let data = UserDefaults(suiteName: group)?.data(forKey: "psst.widget.everyone"),
              let people = try? JSONDecoder().decode([WidgetPerson].self, from: data) else { return [] }
        return people.map { PsstPersonEntity(id: $0.id, name: $0.name) }
    }
}

struct PsstPersonQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PsstPersonEntity] {
        PsstPersonEntity.everyone().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PsstPersonEntity] { PsstPersonEntity.everyone() }

    /// Unless you pick someone: the person at the top of home.
    func defaultResult() async -> PsstPersonEntity? { PsstPersonEntity.everyone().first }
}

/// Sends one Psst to the chosen person, in the background.
struct SendPsstIntent: AppIntent {
    static let title: LocalizedStringResource = "Send a Psst"
    static let description = IntentDescription("Sends a Psst without opening the app.")
    static let openAppWhenRun = false
    /// 7A (18 Oct 2026): from a locked phone, iOS asks for Face ID first.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Person")
    var person: PsstPersonEntity?

    init() {}
    init(person: PsstPersonEntity?) { self.person = person }

    func perform() async throws -> some IntentResult {
        guard let target = person ?? PsstPersonEntity.everyone().first else { throw PsstSendError.nobody }
        try await PsstSender.send(to: target.id)
        return .result()
    }
}

enum PsstSendError: Error, CustomLocalizedStringResourceConvertible {
    case nobody, signedOut, failed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nobody: "Open Psst and invite someone first."
        case .signedOut: "Open Psst once, then try again."
        case .failed: "Your Psst didn't send. Try again."
        }
    }
}

@available(iOS 18.0, *)
struct PsstControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Psst someone"

    @Parameter(title: "Person")
    var person: PsstPersonEntity?
}

@available(iOS 18.0, *)
struct PsstControl: ControlWidget {
    static let kind = "PsstControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: PsstControlConfiguration.self) { configuration in
            let person = configuration.person ?? PsstPersonEntity.everyone().first
            ControlWidgetButton(action: SendPsstIntent(person: person)) {
                Label(person.map { "Psst \($0.name)" } ?? "Psst", systemImage: "cat.fill")
            }
        }
        .displayName("Psst someone")
        .description("Sends a Psst without opening the app.")
    }
}

/// The few calls the button needs: the shared session (refreshed if it's old) and send-signal.
enum PsstSender {
    private struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var userID: UUID
        var expiresAt: Date
    }

    private struct AuthResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private static var baseURL: URL? {
        guard let host = (info["PSSTSupabaseHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !host.hasPrefix("$(") else { return nil }
        return URL(string: host.contains("://") ? host : "https://\(host)")
    }

    private static var anonKey: String { (info["PSSTSupabaseAnonKey"] as? String) ?? "" }

    private static var query: [String: Any]? {
        guard let group = info["PSSTKeychainGroup"] as? String, !group.isEmpty, !group.contains("$(") else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.psst.session",
                kSecAttrAccount as String: "session",
                kSecAttrAccessGroup as String: group]
    }

    /// The newest unanswered doodle from the server (latest_doodle), so the widget can
    /// show one while the app is closed. nil = none; throws when it can't ask.
    struct FetchedDoodle: Decodable {
        let eventId: UUID?
        let connectionId: UUID
        let senderName: String
        let doodle: [[[Double]]]

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id", connectionId = "connection_id", senderName = "sender_name", doodle
        }
    }

    /// Never refreshes the session: a widget can be stopped at any moment, and a
    /// refresh cut off between the server's reply and saving it would leave the app
    /// holding a used token, signed out for good. With an expired token it just
    /// keeps what the app saved; the app refreshes the next time it's opened.
    static func latestDoodle() async throws -> FetchedDoodle? {
        guard let baseURL, let session = load() else { throw PsstSendError.signedOut }
        guard session.expiresAt.timeIntervalSinceNow > 60 else { throw PsstSendError.failed }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/latest_doodle"))
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PsstSendError.failed }
        return try JSONDecoder().decode(FetchedDoodle?.self, from: data)
    }

    /// What widget_state says for this install's read token (1.0.9): the newest
    /// unanswered doodle, and when each person last pssted you and your streak.
    struct WidgetState: Decodable {
        struct Person: Decodable {
            let connectionId: UUID
            let lastReceivedAt: Date?
            let streakDays: Int?

            enum CodingKeys: String, CodingKey {
                case connectionId = "connection_id", lastReceivedAt = "last_received_at", streakDays = "streak_days"
            }
        }

        let doodle: FetchedDoodle?
        let people: [Person]?
    }

    /// The read token the app registered for this account (WidgetReadToken in the app).
    private static var readToken: String? {
        guard let group = info["PSSTAppGroup"] as? String, let defaults = UserDefaults(suiteName: group),
              defaults.string(forKey: "psst.widget.readToken.account") != nil,
              let token = defaults.string(forKey: "psst.widget.readToken"), !token.isEmpty else { return nil }
        return token
    }

    /// Reads widget_state with the read token and the public key only: no session,
    /// so nothing here can rotate or lose it. Throws when there's no token, the
    /// server doesn't know it, or it can't ask; the caller then does as before.
    static func widgetState() async throws -> WidgetState {
        guard let baseURL, let token = readToken else { throw PsstSendError.signedOut }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/widget_state"))
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_token": token])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PsstSendError.failed }
        guard let state = try decoder.decode(WidgetState?.self, from: data) else { throw PsstSendError.signedOut }
        return state
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseTimestamp(string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognized date \(string)"))
        }
        return decoder
    }()

    /// Postgres timestamps: "2026-09-24T06:10:12.123456+00:00", with 0–6 fractional
    /// digits. Mirrors APIClient.parseTimestamp in the app.
    static func parseTimestamp(_ string: String) -> Date? {
        var normalized = string.replacingOccurrences(of: " ", with: "T")
        if let dot = normalized.firstIndex(of: ".") {
            let fractionStart = normalized.index(after: dot)
            let fractionEnd = normalized[fractionStart...].firstIndex { !$0.isNumber } ?? normalized.endIndex
            var digits = String(normalized[fractionStart..<fractionEnd])
            digits = String((digits + "000").prefix(3))
            normalized.replaceSubrange(fractionStart..<fractionEnd, with: digits)
        }
        if let date = withFraction.date(from: normalized) { return date }
        return plain.date(from: normalized)
    }

    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func send(to connection: UUID) async throws {
        guard let baseURL, var session = load() else { throw PsstSendError.signedOut }
        if session.expiresAt.timeIntervalSinceNow < 60 { session = try await refresh(session, baseURL: baseURL) }
        var status = try await post(session, baseURL: baseURL, connection: connection)
        if status == 401 {
            session = try await refresh(session, baseURL: baseURL)
            status = try await post(session, baseURL: baseURL, connection: connection)
        }
        guard (200..<300).contains(status) else { throw PsstSendError.failed }
    }

    private static func post(_ session: Session, baseURL: URL, connection: UUID) async throws -> Int {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/send-signal"))
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "event_id": UUID().uuidString.lowercased(),
            "connection_id": connection.uuidString.lowercased(),
            "effect_id": "psst",
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// Refreshes and saves the session for the app to pick up, straight away and in
    /// place. Never deletes it: if the app rotated the token meanwhile, the app's newer
    /// session is already stored, and is used instead.
    private static func refresh(_ session: Session, baseURL: URL) async throws -> Session {
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw PsstSendError.failed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            // The app may have rotated the token meanwhile: its newer session is stored.
            if let stored = load(), stored.refreshToken != session.refreshToken,
               stored.expiresAt.timeIntervalSinceNow > 60 { return stored }
            throw PsstSendError.failed
        }
        let fresh = Session(accessToken: auth.access_token, refreshToken: auth.refresh_token, userID: auth.user.id,
                            expiresAt: Date().addingTimeInterval(auth.expires_in))
        save(fresh)
        return fresh
    }

    private static func load() -> Session? {
        guard var lookup = query else { return nil }
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func save(_ session: Session) {
        guard let query, let data = try? JSONEncoder().encode(session) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        SecItemUpdate(query as CFDictionary, update as CFDictionary)
    }
}
