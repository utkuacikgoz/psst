import XCTest
@testable import Psst

@MainActor
final class FakeAPI: PsstAPI {
    var isSignedIn = true
    var connections: [ConnectionSummary] = []
    var unseen: [UnseenSignal] = []
    var sentEventIDs: [UUID] = []
    var acked: [UUID] = []
    var sendError: Error?
    var listError: Error?
    /// When set, sends wait until `releaseSend()` is called.
    var holdSends = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var pendingSendCount: Int { held.count }
    func releaseSend() { held.removeFirst().resume() }

    func signUpAnonymously() async throws { isSignedIn = true }
    func setDisplayName(_ name: String) async throws {}
    func listConnections() async throws -> [ConnectionSummary] {
        if let listError { throw listError }
        return connections
    }
    func listUnseen() async throws -> [UnseenSignal] { unseen }
    func ackSignals(_ ids: [UUID]) async throws {
        acked += ids
        unseen.removeAll { ids.contains($0.id) }
    }
    func sendSignal(eventID: UUID, connectionID: UUID, signal: Signal) async throws -> SendResult {
        if holdSends { await withCheckedContinuation { held.append($0) } }
        sentEventIDs.append(eventID)
        if let sendError { throw sendError }
        return SendResult(id: eventID, createdAt: Date(), pushStatus: "accepted", duplicate: false)
    }
    func createInvite() async throws -> CreatedInvite { CreatedInvite(code: "ABCDEFGH", expiresAt: Date()) }
    func previewInvite(code: String) async throws -> InvitePreview { InvitePreview(status: .pending, inviterName: "Ada") }
    func acceptInvite(code: String) async throws -> AcceptedInvite { AcceptedInvite(status: "accepted", connectionId: nil) }
    func removeConnection(_ id: UUID) async throws {}
    func blockUser(_ id: UUID) async throws {}
    func unblockUser(_ id: UUID) async throws {}
    func listBlocked() async throws -> [BlockedPerson] { [] }
    func registerDeviceToken(_ token: String, environment: String) async throws {}
    func deleteAccount() async throws { isSignedIn = false }
    func signOutLocally() { isSignedIn = false }
}

@MainActor
final class LiveStoreTests: XCTestCase {
    private var api: FakeAPI!
    private var store: LiveStore!
    private var defaults: UserDefaults!
    private var suite: String!
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func connection(
        id: UUID = UUID(), name: String = "Ada",
        last: Signal? = nil, fromMe: Bool? = nil, seen: Bool = false, unseen: Int = 0
    ) -> ConnectionSummary {
        ConnectionSummary(
            connectionId: id, otherId: UUID(), otherName: name,
            lastEventId: last == nil ? nil : UUID(), lastFromMe: fromMe, lastEffect: last?.rawValue,
            lastCreatedAt: last == nil ? nil : Date(), lastSeenAt: seen ? Date() : nil, unseenCount: unseen)
    }

    override func setUp() async throws {
        suite = "LiveStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        api = FakeAPI()
        store = LiveStore(api: api, defaults: defaults, now: { [unowned self] in self.clock }, sentDisplayDuration: .zero)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Onboarding

    func testNewInstallAsksForName() async {
        api.isSignedIn = false
        await store.start()
        XCTAssertEqual(store.phase, .needsName)
    }

    func testProfileThenNotificationChoiceThenReady() async throws {
        api.isSignedIn = false
        try await store.createProfile(name: "Ada")
        XCTAssertEqual(store.phase, .needsNotificationChoice)
        store.finishNotificationChoice()
        XCTAssertEqual(store.phase, .ready)

        let restarted = LiveStore(api: api, defaults: defaults)
        await restarted.start()
        XCTAssertEqual(restarted.phase, .ready)
    }

    func testExpiredSessionReturnsToName() async throws {
        try await store.createProfile(name: "Ada")
        store.finishNotificationChoice()
        api.listError = APIError.signedOut
        await store.refresh()
        XCTAssertEqual(store.phase, .needsName)
        XCTAssertFalse(api.isSignedIn)
    }

    // MARK: Sending

    func testTapSendsPsstAndPlaysEffectOnlyAfterAcceptance() async {
        let ada = connection()
        api.connections = [ada]
        await store.refresh()

        await store.tap(ada)?.value
        XCTAssertEqual(api.sentEventIDs.count, 1)
        XCTAssertEqual(store.effects[ada.id]?.signal, .psst)
        XCTAssertEqual(store.effects[ada.id]?.id, api.sentEventIDs.first)
        XCTAssertNil(store.sendStates[ada.id], "Sent clears after its display time")
    }

    func testTapsDuringASendAreIgnored() async {
        let ada = connection()
        api.connections = [ada]
        api.holdSends = true
        let first = store.tap(ada)
        while api.pendingSendCount == 0 { await Task.yield() }
        XCTAssertEqual(store.status(for: ada), .sending(.psst))

        clock += 5
        XCTAssertNil(store.tap(ada), "In-flight send blocks another")
        api.releaseSend()
        await first?.value
        XCTAssertEqual(api.sentEventIDs.count, 1)
    }

    func testRapidRepeatTapIsCoalesced() async {
        let ada = connection()
        await store.tap(ada)?.value
        clock += 0.3
        XCTAssertNil(store.tap(ada))
        clock += 1
        await store.tap(ada)?.value
        XCTAssertEqual(api.sentEventIDs.count, 2)
    }

    func testFailedSendShowsRetryAndRetryReusesEventID() async {
        let ada = connection()
        api.sendError = APIError.offline
        await store.tap(ada)?.value
        XCTAssertEqual(store.status(for: ada), .notSent(.psst))
        XCTAssertTrue(store.isOffline)

        api.sendError = nil
        await store.tap(ada)?.value
        XCTAssertEqual(api.sentEventIDs.count, 2)
        XCTAssertEqual(api.sentEventIDs[0], api.sentEventIDs[1], "Retry must reuse the event ID")
        XCTAssertFalse(store.isOffline)
    }

    func testServerErrorsAlsoOfferRetry() async {
        let ada = connection()
        api.sendError = APIError.server(status: 500, code: "unknown")
        await store.tap(ada)?.value
        XCTAssertEqual(store.status(for: ada), .notSent(.psst))
    }

    func testRateLimitedShowsPaused() async {
        let ada = connection()
        api.sendError = APIError.server(status: 429, code: "rate_limited")
        await store.tap(ada)?.value
        XCTAssertEqual(store.status(for: ada), .paused(.psst))
    }

    func testEndedConnectionIsRemovedWithANotice() async {
        let ada = connection()
        api.connections = [ada]
        await store.refresh()
        api.sendError = APIError.server(status: 403, code: "not_connected")
        await store.tap(ada)?.value
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(store.notice, "You're no longer connected with Ada.")
        XCTAssertNil(store.effects[ada.id])
    }

    // MARK: Status wording inputs

    func testRowStatusComesFromServerEvidence() {
        XCTAssertEqual(store.status(for: connection()), .ready(.psst))
        XCTAssertEqual(store.status(for: connection(last: .psst, fromMe: true)), .sentEarlier(.psst))
        XCTAssertEqual(store.status(for: connection(last: .psst, fromMe: true, seen: true)), .seen(.psst))
        XCTAssertEqual(store.status(for: connection(last: .psst, fromMe: false)), .received(from: "Ada", .psst))
    }

    // MARK: Receiving

    func testUnseenSignalsAreAckedOnlyWhenHomeIsVisible() async {
        let ada = connection()
        api.connections = [ada]
        let older = UnseenSignal(id: UUID(), connectionId: ada.id, senderId: UUID(), senderName: "Ada",
                                 effectId: "psst", createdAt: Date(timeIntervalSince1970: 1))
        let newer = UnseenSignal(id: UUID(), connectionId: ada.id, senderId: UUID(), senderName: "Ada",
                                 effectId: "psst", createdAt: Date(timeIntervalSince1970: 2))
        let stranger = UnseenSignal(id: UUID(), connectionId: UUID(), senderId: UUID(), senderName: "?",
                                    effectId: "psst", createdAt: Date())
        api.unseen = [newer, older, stranger]

        store.isHomeVisible = false
        await store.refresh()
        XCTAssertTrue(api.acked.isEmpty)
        XCTAssertNil(store.effects[ada.id])

        store.isHomeVisible = true
        await store.refresh()
        XCTAssertEqual(Set(api.acked), [older.id, newer.id], "Only signals for rows on screen")
        XCTAssertEqual(store.effects[ada.id], EffectTrigger(id: newer.id, signal: .psst))
        XCTAssertEqual(store.latestEffect?.id, newer.id)
    }

    func testSendBackIsIdempotentAndAcksTheOriginal() async {
        let payload = SignalPayload(eventID: UUID(), connectionID: UUID(), signal: .psst)
        let first = await store.sendBack(payload)
        let second = await store.sendBack(payload)
        XCTAssertTrue(first && second)
        XCTAssertEqual(api.acked, [payload.eventID, payload.eventID])
        XCTAssertEqual(api.sentEventIDs, [.reply(to: payload.eventID), .reply(to: payload.eventID)])
        XCTAssertNotEqual(UUID.reply(to: payload.eventID), payload.eventID)
    }

    func testFailedSendBackReportsFailure() async {
        api.sendError = APIError.offline
        let sent = await store.sendBack(SignalPayload(eventID: UUID(), connectionID: UUID(), signal: .psst))
        XCTAssertFalse(sent)
    }

    func testOpeningANotificationAcksAndPlaysIt() async {
        let payload = SignalPayload(eventID: UUID(), connectionID: UUID(), signal: .psst)
        await store.openedNotification(payload)
        XCTAssertEqual(api.acked, [payload.eventID])
        XCTAssertEqual(store.effects[payload.connectionID], EffectTrigger(id: payload.eventID, signal: .psst))
    }

    func testDeleteAccountResetsToOnboarding() async throws {
        try await store.createProfile(name: "Ada")
        store.finishNotificationChoice()
        try await store.deleteAccount()
        XCTAssertEqual(store.phase, .needsName)
        XCTAssertTrue(store.connections.isEmpty)
    }
}

@MainActor
final class LiveParsingTests: XCTestCase {
    func testPostgresTimestamps() throws {
        let micro = try XCTUnwrap(APIClient.parseTimestamp("2026-09-24T06:10:12.123456+00:00"))
        XCTAssertEqual(micro.timeIntervalSince1970, 1_790_230_212.123, accuracy: 0.001)
        XCTAssertNotNil(APIClient.parseTimestamp("2026-09-24T06:10:12+00:00"))
        XCTAssertNotNil(APIClient.parseTimestamp("2026-09-24T06:10:12.5Z"))
        XCTAssertNotNil(APIClient.parseTimestamp("2026-09-24 06:10:12.5+02:00"))
        XCTAssertNil(APIClient.parseTimestamp("yesterday"))
    }

    func testDecodesListConnectionsRow() throws {
        let json = """
        [{"connection_id":"6f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f","other_id":"7f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
          "other_name":"Ada","my_favorite":"duck","last_event_id":null,"last_from_me":null,"last_effect":null,
          "last_created_at":null,"last_seen_at":null,"unseen_count":0},
         {"connection_id":"8f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f","other_id":"9f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
          "other_name":"Emre","my_favorite":"psst","last_event_id":"af1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
          "last_from_me":true,"last_effect":"psst","last_created_at":"2026-09-24T06:10:12.123456+00:00",
          "last_seen_at":"2026-09-24T06:11:00+00:00","unseen_count":2}]
        """
        let rows = try APIClient.decoder.decode([ConnectionSummary].self, from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.otherName), ["Ada", "Emre"])
        XCTAssertNil(rows[0].lastSignal)
        XCTAssertEqual(rows[1].lastSignal, .psst)
        XCTAssertEqual(rows[1].unseenCount, 2)
        XCTAssertNotNil(rows[1].lastSeenAt)
    }

    func testDecodesInvitePreviewStatuses() throws {
        let preview = try APIClient.decoder.decode(
            InvitePreview.self, from: Data(#"{"status":"already_connected","inviter_name":"Ada"}"#.utf8))
        XCTAssertEqual(preview, InvitePreview(status: .alreadyConnected, inviterName: "Ada"))
    }

    func testErrorCodes() {
        XCTAssertEqual(APIClient.errorCode(from: Data(#"{"code":"PT403","message":"not_connected"}"#.utf8)), "not_connected")
        XCTAssertEqual(APIClient.errorCode(from: Data(#"{"error":"rate_limited"}"#.utf8)), "rate_limited")
        XCTAssertEqual(APIClient.errorCode(from: Data(#"{"error_code":"refresh_token_not_found","msg":"x"}"#.utf8)),
                       "refresh_token_not_found")
        XCTAssertEqual(APIClient.errorCode(from: Data("<html>".utf8)), "unknown")
    }

    func testNotificationPayload() {
        let payload = SignalPayload(userInfo: [
            "aps": ["alert": ["title": "Ada", "body": "Oi"]],
            "psst": ["event_id": "6f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
                     "connection_id": "7f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
                     "effect_id": "psst"],
        ])
        XCTAssertEqual(payload?.signal, .psst)
        XCTAssertEqual(payload?.eventID, UUID(uuidString: "6f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f"))
        XCTAssertNil(SignalPayload(userInfo: ["psst": ["event_id": "x", "connection_id": "y", "effect_id": "psst"]]))
        XCTAssertNil(SignalPayload(userInfo: ["aps": [:]]))
        // Signals removed from the app (Squeeze, Oi, Duck) are ignored, not misread.
        XCTAssertNil(SignalPayload(userInfo: ["psst": ["event_id": "6f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
                                                      "connection_id": "7f1c2d3e-4b5a-4c6d-8e7f-1a2b3c4d5e6f",
                                                      "effect_id": "duck"]]))
    }

    func testInviteLinks() {
        XCTAssertEqual(InviteLink.code(from: URL(string: "psst://invite/abcd-efgh")!), "ABCDEFGH")
        XCTAssertEqual(CreatedInvite(code: "ABCDEFGH", expiresAt: Date()).link.absoluteString, "psst://invite/ABCDEFGH")
        XCTAssertEqual(CreatedInvite(code: "ABCDEFGH", expiresAt: Date()).displayCode, "ABCD EFGH")
        XCTAssertNil(InviteLink.code(from: URL(string: "psst://other/ABCD")!))
        XCTAssertNil(InviteLink.code(from: URL(string: "https://invite/ABCD")!))
        XCTAssertNil(InviteLink.code(from: URL(string: "psst://invite")!))
    }
}
