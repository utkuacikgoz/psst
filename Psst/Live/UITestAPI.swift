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
        case loadFailure
        case settingsFailure
        case features
        case returning
        case superArrival
        /// The tour's people, already signed in, for App Store screenshots.
        case store
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
        if scenario != .tour {
            defaults.set(true, forKey: LiveStore.profileKey)
            defaults.set(true, forKey: LiveStore.notificationChoiceKey)
        }
        if scenario == .features || scenario == .returning || scenario == .superArrival {
            defaults.set(true, forKey: LiveStore.coachKey)
            defaults.set(true, forKey: LiveStore.superHintKey)
            if scenario != .returning { defaults.set(true, forKey: LiveStore.featureIntroKey) }
        }
        if [.store, .loadFailure, .settingsFailure].contains(scenario) {
            defaults.set(true, forKey: LiveStore.coachKey)
            defaults.set(true, forKey: LiveStore.superHintKey)
            defaults.set(true, forKey: LiveStore.featureIntroKey)
        }
        return LiveStore(api: UITestAPI(scenario: scenario), defaults: defaults)
    }

    private let ada = UUID()
    private let emre = UUID()
    private let sam = UUID()
    private let kim = UUID()
    private var samTaps = 0
    private var last: [UUID: (fromMe: Bool, signal: Signal, seen: Bool)] = [:]
    private var unseen: [UnseenSignal] = []
    private var lastDates: [UUID: Date] = [:]
    private var names: [UUID: String] = [:]

    private let scenario: Scenario
    private var connectionsCalls = 0
    private var blockedCalls = 0
    private var invitesCalls = 0
    var isSignedIn: Bool

    init(scenario: Scenario) {
        self.scenario = scenario
        isSignedIn = scenario != .tour
        guard scenario != .empty else { return }
        names = scenario == .store ? [ada: "Mia", emre: "Zoe", sam: "Ava"] : [ada: "Ada", emre: "Emre", sam: "Sam"]
        last = [ada: (false, .psst, false), emre: (true, .psst, true)]
        lastDates = [ada: Date().addingTimeInterval(scenario == .tour ? 0 : -720),
                     emre: Date().addingTimeInterval(-90000)]
        unseen = [UnseenSignal(id: UUID(), connectionId: ada, senderId: UUID(), senderName: names[ada] ?? "Ada",
                               effectId: scenario == .superArrival ? Signal.superPsst.rawValue : Signal.psst.rawValue, createdAt: Date())]
    }

    func signUpAnonymously() async throws { isSignedIn = true }
    func setDisplayName(_ name: String) async throws {}

    func listConnections() async throws -> [ConnectionSummary] {
        connectionsCalls += 1
        if scenario == .loadFailure, connectionsCalls == 1 {
            // Let launch and home join the same in-flight request, as a real
            // network response would, before presenting the retry state.
            try await Task.sleep(for: .seconds(1))
            throw APIError.server(status: 500, code: "server_error")
        }
        return [ada, emre, sam, kim].compactMap { id in
            guard let name = names[id] else { return nil }
            let event = last[id]
            return ConnectionSummary(
                connectionId: id, otherId: id, otherName: name,
                lastEventId: event == nil ? nil : UUID(), lastFromMe: event?.fromMe,
                lastEffect: event?.signal.rawValue, lastCreatedAt: event == nil ? nil : lastDates[id],
                lastSeenAt: event?.seen == true ? Date() : nil,
                unseenCount: unseen.filter { $0.connectionId == id }.count)
        }
    }

    func listUnseen() async throws -> [UnseenSignal] { [.loadFailure, .settingsFailure].contains(scenario) ? [] : unseen }

    func ackSignals(_ ids: [UUID]) async throws {
        unseen.removeAll { ids.contains($0.id) }
    }

    /// Zoe's sends take a moment (to show "Sending…"). Ava's first fails as if
    /// offline; the next hits the pacing limit.
    func sendSignal(eventID: UUID, connectionID: UUID, signal: Signal) async throws -> SendResult {
        if connectionID == sam {
            samTaps += 1
            try await Task.sleep(for: .milliseconds(300))
            throw samTaps == 1 ? APIError.offline : APIError.server(status: 429, code: "rate_limited")
        }
        if connectionID == emre {
            try await Task.sleep(for: .milliseconds(1500))
        }
        if signal == .superPsst {
            if usedSuper { throw APIError.server(status: 409, code: "super_daily_limit") }
            usedSuper = true
        }
        lastDates[connectionID] = Date()
        last[connectionID] = (true, signal, false)
        // Mia pssted just before, so answering her is a same moment.
        return SendResult(id: eventID, createdAt: Date(), pushStatus: "accepted", duplicate: false,
                          sameMoment: connectionID == ada)
    }


    private var usedSuper = false
    private var superEffectsEnabled = true
    func activity(monthStart: Date) async throws -> [ActivitySummary] {
        names.map { id, name in ActivitySummary(connectionId: id, otherName: name,
            sentAll: id == emre ? 212 : id == ada ? 148 : 31, receivedAll: id == ada ? 260 : id == emre ? 96 : 12,
            sentMonth: id == emre ? 12 : 3, receivedMonth: id == ada ? 18 : 2) }
    }
    func superAllowance() async throws -> SuperAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return SuperAllowance(remaining: usedSuper ? 0 : 1, unlimited: false,
            resetsAt: calendar.startOfDay(for: Date()).addingTimeInterval(86400),
            effectsEnabled: superEffectsEnabled)
    }
    func setSuperEffects(_ enabled: Bool) async throws { superEffectsEnabled = enabled }

    func createInvite() async throws -> CreatedInvite {
        CreatedInvite(code: "K7QX4MPA", expiresAt: Date().addingTimeInterval(7 * 86_400), maxUses: 10)
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        InvitePreview(status: .pending, inviterName: "Lily")
    }

    func acceptInvite(code: String) async throws -> AcceptedInvite {
        names[kim] = "Lily"
        return AcceptedInvite(status: "accepted", connectionId: kim)
    }

    func removeConnection(_ id: UUID) async throws { names[id] = nil }
    func blockUser(_ id: UUID) async throws { names[id] = nil }
    func unblockUser(_ id: UUID) async throws {}
    func reportUser(_ id: UUID) async throws { names[id] = nil }
    func listBlocked() async throws -> [BlockedPerson] {
        blockedCalls += 1
        if scenario == .settingsFailure, blockedCalls == 1 { throw APIError.offline }
        return []
    }
    private var openInvites: [String] = ["K7QX4MPA"]
    func listOpenInvites() async throws -> [OpenInvite] {
        invitesCalls += 1
        if scenario == .settingsFailure, invitesCalls == 1 { throw APIError.offline }
        return openInvites.map { OpenInvite(code: $0, createdAt: Date(), expiresAt: Date().addingTimeInterval(6 * 86_400)) }
    }
    func revokeInvite(code: String) async throws { openInvites.removeAll { $0 == code } }
    func setNotificationSound(_ file: String) async throws {}
    func setNotificationStatus(_ enabled: Bool) async throws {}
    func registerDeviceToken(_ token: String, environment: String) async throws {}
    func deleteAccount() async throws { isSignedIn = false }
    func signOutLocally() { isSignedIn = false }
}
#endif
