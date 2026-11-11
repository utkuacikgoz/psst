import XCTest
@testable import Psst

/// 1.0.9 picks (owner, 10 Nov 2026): the joiner's notifications ask (3A), the widget
/// tip and New in Psst (4A), the streak saver (5A), pushes that open a band (5A, 11A),
/// the reminder's kind (13A) and the Share my week card (14A).
@MainActor
final class GrowthTests: XCTestCase {
    private var api: FakeAPI!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "GrowthTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        api = FakeAPI()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func person(_ id: UUID, event: UUID?, fromMe: Bool?, at date: Date? = nil, streak: Int? = nil) -> ConnectionSummary {
        ConnectionSummary(connectionId: id, otherId: id, otherName: "Kim", lastEventId: event, lastFromMe: fromMe,
                          lastEffect: event == nil ? nil : "psst", lastCreatedAt: event == nil ? nil : (date ?? Date()),
                          lastSeenAt: nil, unseenCount: 0, streakDays: streak)
    }

    /// A new account, as onboarding makes it.
    private func newAccount() async throws -> LiveStore {
        api.isSignedIn = false
        let store = LiveStore(api: api, defaults: defaults, sentDisplayDuration: .zero)
        try await store.createProfile(name: "Utku")
        return store
    }

    func testTwoWayMeansTheLatestPsstChangedDirectionOrAStreakBegan() {
        let id = UUID()
        let theirs = Date(timeIntervalSince1970: 1_000)
        let fromThem = person(id, event: UUID(), fromMe: false, at: theirs)
        let fromMe = person(id, event: UUID(), fromMe: true)
        XCTAssertEqual(LiveStore.firstTwoWayExchange(from: [fromThem], to: [fromMe])?.connectionID, id)
        XCTAssertEqual(LiveStore.firstTwoWayExchange(from: [fromThem], to: [fromMe])?.theirLastPsst, theirs)
        XCTAssertNil(LiveStore.firstTwoWayExchange(from: [fromMe], to: [person(id, event: UUID(), fromMe: true)]),
                     "two of yours in a row is not an exchange")
        XCTAssertNil(LiveStore.firstTwoWayExchange(from: [], to: [fromMe]), "nothing to compare with")
        XCTAssertNil(LiveStore.firstTwoWayExchange(from: [person(id, event: nil, fromMe: nil)], to: [fromMe]))
        XCTAssertNotNil(LiveStore.firstTwoWayExchange(from: [fromMe], to: [person(id, event: fromMe.lastEventId, fromMe: true, streak: 1)]))
    }

    func testWidgetTipComesOnceAfterANewAccountsFirstExchange() async throws {
        let store = try await newAccount()
        XCTAssertFalse(store.whatsNewDue, "new accounts get the tip, not New in Psst")
        let id = UUID()
        api.connections = [person(id, event: UUID(), fromMe: false)]
        await store.refresh()
        XCTAssertNil(store.widgetTip)
        api.connections = [person(id, event: UUID(), fromMe: true)]
        await store.refresh()
        XCTAssertEqual(store.widgetTip?.connectionID, id)
        XCTAssertFalse(store.notificationAskDue, "they shared no link: not a joiner")

        // Still there after a relaunch until it has shown.
        let relaunched = LiveStore(api: api, defaults: defaults)
        XCTAssertEqual(relaunched.widgetTip?.connectionID, id)
        relaunched.dismissWidgetTip()
        XCTAssertNil(LiveStore(api: api, defaults: defaults).widgetTip, "once")
    }

    func testExistingAccountsGetNewInPsstOnceAndNoWidgetTip() async {
        defaults.set(true, forKey: LiveStore.profileKey)
        let store = LiveStore(api: api, defaults: defaults)
        XCTAssertTrue(store.whatsNewDue)
        let id = UUID()
        api.connections = [person(id, event: UUID(), fromMe: false)]
        await store.refresh()
        api.connections = [person(id, event: UUID(), fromMe: true)]
        await store.refresh()
        XCTAssertNil(store.widgetTip, "New in Psst already tells them")
        store.dismissWhatsNew()
        XCTAssertFalse(LiveStore(api: api, defaults: defaults).whatsNewDue)
    }

    func testAJoinersFirstExchangeAsksAboutNotificationsOnce() async throws {
        let store = try await newAccount()
        _ = try await store.acceptInvite(code: "AB12CD34")
        let id = UUID()
        api.connections = [person(id, event: UUID(), fromMe: false)]
        await store.refresh()
        XCTAssertFalse(store.notificationAskDue)
        api.connections = [person(id, event: UUID(), fromMe: true)]
        await store.refresh()
        XCTAssertTrue(store.notificationAskDue)
        store.finishNotificationAsk()
        api.connections = [person(id, event: UUID(), fromMe: false)]
        await store.refresh()
        XCTAssertFalse(store.notificationAskDue)
        XCTAssertFalse(LiveStore(api: api, defaults: defaults).notificationAskDue)
    }

    func testOnlyOneOneTimeThingPerVisit() {
        let store = LiveStore(api: api, defaults: defaults)
        XCTAssertFalse(store.promptedThisVisit)
        store.notePrompted()
        XCTAssertTrue(store.promptedThisVisit)
        store.startNewVisit()
        XCTAssertFalse(store.promptedThisVisit)
        store.dismissCoach()
        XCTAssertTrue(store.promptedThisVisit, "the first tip counts too")
    }

    func testStreakSaverIsOfferedOnceWhenAStreakFirstReachesThree() async {
        defaults.set(true, forKey: LiveStore.profileKey)
        let store = LiveStore(api: api, defaults: defaults)
        let kim = UUID(), ada = UUID()
        api.connections = [person(kim, event: UUID(), fromMe: true, streak: 2), person(ada, event: UUID(), fromMe: true, streak: 2)]
        await store.refresh()
        XCTAssertNil(store.streakSaverOffer)
        api.connections = [person(kim, event: UUID(), fromMe: true, streak: 3), person(ada, event: UUID(), fromMe: true, streak: 2)]
        await store.refresh()
        XCTAssertEqual(store.streakSaverOffer, kim)
        store.finishStreakSaverOffer()
        api.connections = [person(kim, event: UUID(), fromMe: true, streak: 3), person(ada, event: UUID(), fromMe: true, streak: 3)]
        await store.refresh()
        XCTAssertNil(store.streakSaverOffer, "once ever")
    }

    func testStreakRemindersFollowTheServer() async {
        let store = LiveStore(api: api, defaults: defaults)
        let unknown = await store.loadStreakSaver()
        XCTAssertNil(unknown, "unknown until the server answers")
        api.streakSaver = StreakSaverStatus(enabled: false, unlimited: false, freezesLeft: 1)
        let known = await store.loadStreakSaver()
        XCTAssertEqual(known?.enabled, false)
        let saved = await store.setStreakReminders(true)
        XCTAssertTrue(saved)
        XCTAssertEqual(api.streakReminderSettings, [true])
        XCTAssertEqual(store.streakSaver?.enabled, true)
    }

    func testStreakSaverStatusDecodes() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(StreakSaverStatus.self,
                                        from: Data(#"{"enabled": true, "unlimited": false, "freezes_left": 1}"#.utf8))
        XCTAssertEqual(status, StreakSaverStatus(enabled: true, unlimited: false, freezesLeft: 1))
    }

    func testPushesThatOpenABandAndTheReminderKind() {
        let id = UUID()
        XCTAssertEqual(AppDelegate.focusedConnection(["psst": ["streak_reminder": true, "connection_id": id.uuidString]]), id)
        XCTAssertEqual(AppDelegate.focusedConnection(["psst": ["quiet_week": true, "connection_id": id.uuidString]]), id)
        XCTAssertNil(AppDelegate.focusedConnection(["psst": ["recap": true]]))
        XCTAssertNil(AppDelegate.focusedConnection(["psst": ["streak_reminder": true, "connection_id": "nope"]]))
        let reminder: [AnyHashable: Any] = ["psst": ["invite_reminder": true, "code": "AB12CD34", "kind": "doodle"]]
        XCTAssertEqual(AppDelegate.inviteReminderCode(reminder), "AB12CD34")
        XCTAssertEqual(AppDelegate.inviteReminderKind(reminder), "doodle")
        XCTAssertNil(AppDelegate.inviteReminderKind(["psst": ["invite_reminder": true, "code": "AB12CD34"]]))
    }

    func testWidgetTipLineAndSavedForm() {
        let now = Date(timeIntervalSince1970: 100_000)
        let tip = WidgetTipPerson(connectionID: UUID(), theirLastPsst: now.addingTimeInterval(-30))
        XCTAssertEqual(tip.line(now: now), "pssted you just now")
        XCTAssertEqual(WidgetTipPerson(connectionID: tip.connectionID, theirLastPsst: now.addingTimeInterval(-7_200)).line(now: now),
                       "pssted you 2h ago")
        XCTAssertEqual(WidgetTipPerson(saved: tip.saved), tip)
        XCTAssertNil(WidgetTipPerson(saved: "junk"))
        XCTAssertNil(WidgetTipPerson(saved: nil))
    }

    func testShareMyWeekShowsAnInitialOnlyAndOnlyTheNumberOnesStreak() {
        XCTAssertEqual(ShareWeekCard.initial(of: "Kim"), "K.")
        XCTAssertEqual(ShareWeekCard.initial(of: " ada lovelace"), "A.")
        XCTAssertNil(ShareWeekCard.initial(of: "  "))
        let kim = UUID(), ada = UUID()
        func recap(streakWith id: UUID, days: Int) -> WeeklyRecap {
            WeeklyRecap(weekStart: "2026-11-02", weekEnd: "2026-11-08", total: 23, sent: 12, received: 11,
                        top: .init(connectionId: kim, name: "Kim", count: 9, still: false),
                        streak: .init(connectionId: id, name: "Someone", days: days))
        }
        XCTAssertEqual(ShareWeekCard.streakDays(for: recap(streakWith: kim, days: 6), connections: []), 6)
        XCTAssertNil(ShareWeekCard.streakDays(for: recap(streakWith: ada, days: 9), connections: []),
                     "never someone else's streak next to their initial")
        XCTAssertEqual(ShareWeekCard.streakDays(for: recap(streakWith: ada, days: 9),
                                                connections: [person(kim, event: UUID(), fromMe: true, streak: 4)]), 4)
        XCTAssertEqual(ShareWeekCard.link.absoluteString, "https://psstapp.fun/?ct=share-week")
    }
}
