import XCTest
@testable import Psst

@MainActor
final class FeatureTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "FeatureTests.\(UUID())"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func connection() -> ConnectionSummary {
        ConnectionSummary(connectionId: UUID(), otherId: UUID(), otherName: "Ada", lastEventId: nil,
            lastFromMe: nil, lastEffect: nil, lastCreatedAt: nil, lastSeenAt: nil, unseenCount: 0)
    }
    func testIntroDismissalPersistsWithoutSending() {
        let api = FakeAPI(); defaults.set(true, forKey: LiveStore.profileKey)
        let store = LiveStore(api: api, defaults: defaults)
        XCTAssertTrue(store.isExistingUser); XCTAssertFalse(store.featureIntroSeen)
        store.dismissFeatureIntro()
        let restarted = LiveStore(api: api, defaults: defaults)
        XCTAssertTrue(restarted.featureIntroSeen); XCTAssertTrue(api.sentEventIDs.isEmpty)
    }
    func testNewUserCoachIntroducesSuperWithoutSeparateUpdateSheet() {
        let store = LiveStore(api: FakeAPI(), defaults: defaults)
        XCTAssertFalse(store.isExistingUser)
        store.dismissCoach()
        XCTAssertTrue(store.featureIntroSeen); XCTAssertTrue(store.superHintSeen)
    }
    func testFailedSuperRetryReusesEventAndBlocksAnotherSuper() async {
        let api = FakeAPI(); let person = connection(); api.connections = [person]; api.sendError = APIError.offline
        let store = LiveStore(api: api, defaults: defaults, sentDisplayDuration: .zero)
        await store.refresh()
        await store.sendSuper(person)?.value
        XCTAssertNil(store.sendSuper(person))
        await store.tap(person)?.value
        XCTAssertEqual(api.sentEventIDs.count, 2)
        XCTAssertEqual(api.sentEventIDs[0], api.sentEventIDs[1])
        XCTAssertEqual(store.status(for: person), .notSent(.superPsst))
    }
    func testDailyLimitDoesNotLeaveSuperAsRetryOnOrdinaryTap() async {
        let api = FakeAPI(); let person = connection(); api.connections = [person]
        api.sendError = APIError.server(status: 409, code: "super_daily_limit")
        let store = LiveStore(api: api, defaults: defaults, sentDisplayDuration: .zero)
        await store.refresh(); await store.sendSuper(person)?.value
        XCTAssertNil(store.sendStates[person.id]); XCTAssertNotNil(store.notice)
        api.sendError = nil; await store.tap(person)?.value
        XCTAssertNil(store.sendStates[person.id])
    }
    func testSuperPushDecodesAndArrivalPlaysSuper() async {
        let api = FakeAPI(); let person = connection(); api.connections = [person]
        let event = UUID()
        let payload = SignalPayload(userInfo: ["psst": ["event_id":event.uuidString,
            "connection_id":person.id.uuidString,"effect_id":"super_psst"]])!
        let store = LiveStore(api: api, defaults: defaults)
        await store.openedNotification(payload)
        XCTAssertEqual(store.arrival?.kind, .superPsst)
        XCTAssertEqual(store.latestEffect?.signal, .superPsst)
    }
    func testNotificationReplyToSuperIsOrdinaryAndDoesNotSpendAllowance() async {
        let api = FakeAPI(); let person = connection()
        let store = LiveStore(api: api, defaults: defaults)
        let success = await store.sendBack(SignalPayload(eventID: UUID(), connectionID: person.id, signal: .superPsst))
        XCTAssertTrue(success); XCTAssertEqual(api.sentSignals, [.psst])
    }
    func testMutedPreviouslyQueuedPushOpensAsOrdinaryPsst() async {
        let api = FakeAPI(); let person = connection(); api.connections = [person]
        defaults.set(false, forKey: "psst.superEffectsEnabled")
        let store = LiveStore(api: api, defaults: defaults)
        await store.openedNotification(SignalPayload(eventID: UUID(), connectionID: person.id, signal: .superPsst))
        XCTAssertEqual(store.arrival?.kind, .signal); XCTAssertEqual(store.latestEffect?.signal, .psst)
    }
    func testSuperNotificationKeepsCompatiblePsstRouting() {
        let event = UUID(), person = connection()
        let payload = SignalPayload(userInfo: ["psst": ["event_id":event.uuidString,
            "connection_id":person.id.uuidString,"effect_id":"psst","super_psst":true]])
        XCTAssertEqual(payload?.signal, .superPsst)
    }
    func testTimestampDoesNotClaimFutureTimeAndHonorsDayBoundary() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 86400 * 100 + 20)
        XCTAssertEqual(ExchangeTime.label(now.addingTimeInterval(10), now: now, calendar: calendar), "Just now")
        XCTAssertEqual(ExchangeTime.label(now.addingTimeInterval(-120), now: now, calendar: calendar), "2m ago")
        XCTAssertEqual(ExchangeTime.label(now.addingTimeInterval(-3600), now: now, calendar: calendar), "Yesterday")
    }
}
