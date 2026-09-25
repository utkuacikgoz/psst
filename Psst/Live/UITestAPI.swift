#if DEBUG
import Foundation

/// A scripted backend for the screenshot UI tests. Compiled into Debug builds only,
/// and used only when the app is launched with `-PsstUITestLive <scenario>`.
/// The people here are test fixtures, never shown in a normal launch.
@MainActor
final class UITestAPI: PsstAPI {
    enum Scenario: String {
        /// Starts at onboarding, then a home screen with three connections.
        case tour
        /// Signed in with no connections yet.
        case empty
    }

    static let defaultsSuite = "psst.uitest"

    /// Returns a store backed by this API when the launch arguments ask for one.
    static func storeFromLaunchArguments() -> LiveStore? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PsstUITestLive"), index + 1 < arguments.count,
              let scenario = Scenario(rawValue: arguments[index + 1]),
              let defaults = UserDefaults(suiteName: defaultsSuite)
        else { return nil }
        defaults.removePersistentDomain(forName: defaultsSuite)
        if scenario == .empty {
            defaults.set(true, forKey: LiveStore.profileKey)
            defaults.set(true, forKey: LiveStore.notificationChoiceKey)
        }
        return LiveStore(api: UITestAPI(scenario: scenario), defaults: defaults)
    }

    private let ada = UUID()
    private let emre = UUID()
    private let sam = UUID()
    private var last: [UUID: (fromMe: Bool, signal: Signal, seen: Bool)] = [:]
    private var unseen: [UnseenSignal] = []
    private var names: [UUID: String] = [:]

    var isSignedIn: Bool

    init(scenario: Scenario) {
        isSignedIn = scenario == .empty
        guard scenario == .tour else { return }
        names = [ada: "Ada", emre: "Emre", sam: "Sam"]
        last = [ada: (false, .psst, false), emre: (true, .psst, true)]
        unseen = [UnseenSignal(id: UUID(), connectionId: ada, senderId: UUID(), senderName: "Ada",
                               effectId: Signal.psst.rawValue, createdAt: Date())]
    }

    func signUpAnonymously() async throws { isSignedIn = true }
    func setDisplayName(_ name: String) async throws {}

    func listConnections() async throws -> [ConnectionSummary] {
        [ada, emre, sam].compactMap { id in
            guard let name = names[id] else { return nil }
            let event = last[id]
            return ConnectionSummary(
                connectionId: id, otherId: id, otherName: name,
                lastEventId: event == nil ? nil : UUID(), lastFromMe: event?.fromMe,
                lastEffect: event?.signal.rawValue, lastCreatedAt: event == nil ? nil : Date(),
                lastSeenAt: event?.seen == true ? Date() : nil,
                unseenCount: unseen.filter { $0.connectionId == id }.count)
        }
    }

    func listUnseen() async throws -> [UnseenSignal] { unseen }

    func ackSignals(_ ids: [UUID]) async throws {
        unseen.removeAll { ids.contains($0.id) }
    }

    /// Emre's sends take a moment (to show "Sending…"); Sam's fail as if offline.
    func sendSignal(eventID: UUID, connectionID: UUID, signal: Signal) async throws -> SendResult {
        if connectionID == sam {
            try await Task.sleep(for: .milliseconds(300))
            throw APIError.offline
        }
        if connectionID == emre {
            try await Task.sleep(for: .milliseconds(1500))
        }
        last[connectionID] = (true, signal, false)
        return SendResult(id: eventID, createdAt: Date(), pushStatus: "accepted", duplicate: false)
    }


    func createInvite() async throws -> CreatedInvite {
        CreatedInvite(code: "K7QX4MPA", expiresAt: Date().addingTimeInterval(7 * 86_400))
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        InvitePreview(status: .pending, inviterName: "Kim")
    }

    func acceptInvite(code: String) async throws -> AcceptedInvite {
        AcceptedInvite(status: "accepted", connectionId: nil)
    }

    func removeConnection(_ id: UUID) async throws { names[id] = nil }
    func blockUser(_ id: UUID) async throws { names[id] = nil }
    func unblockUser(_ id: UUID) async throws {}
    func listBlocked() async throws -> [BlockedPerson] { [] }
    func registerDeviceToken(_ token: String, environment: String) async throws {}
    func deleteAccount() async throws { isSignedIn = false }
    func signOutLocally() { isSignedIn = false }
}
#endif
