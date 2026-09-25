import XCTest
@testable import Psst

final class LocalExchangeTests: XCTestCase {
    private final class Clock {
        var time = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { time += seconds }
    }

    private var clock: Clock!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        clock = Clock()
        suiteName = "LocalExchangeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeExchange() -> LocalExchange {
        let clock = clock!
        return LocalExchange(defaults: defaults, now: { clock.time })
    }

    func testEveryTapSendsPsst() {
        let exchange = makeExchange()
        XCTAssertEqual(exchange.tapSignal(for: .me), .psst)
        XCTAssertEqual(exchange.tapSignal(for: .alex), .psst)
        XCTAssertTrue(exchange.events.isEmpty)
        XCTAssertEqual(exchange.status(for: .me), .ready(.psst))
    }

    func testEachSendHasAUniqueID() {
        let exchange = makeExchange()
        exchange.send(.psst, from: .me)
        clock.advance(2)
        exchange.send(.psst, from: .me)
        XCTAssertEqual(exchange.events.count, 2)
        XCTAssertEqual(Set(exchange.events.map(\.id)).count, 2)
    }

    func testRetryWithSameIDDoesNotDuplicate() {
        let exchange = makeExchange()
        let id = UUID()
        guard case .played(let first) = exchange.send(.psst, from: .me, id: id) else {
            return XCTFail("first send should play")
        }
        clock.advance(5)
        XCTAssertEqual(exchange.send(.psst, from: .me, id: id), .alreadyRecorded(first))
        XCTAssertEqual(exchange.events.count, 1)
    }

    func testRapidRepeatTapIsCoalesced() {
        let exchange = makeExchange()
        exchange.send(.psst, from: .me)
        clock.advance(0.3)
        XCTAssertEqual(exchange.send(.psst, from: .me), .tooSoon)
        XCTAssertEqual(exchange.events.count, 1)
    }

    func testBurstPausesThenResumes() {
        let exchange = makeExchange()
        for _ in 0..<LocalExchange.burstLimit {
            guard case .played = exchange.send(.psst, from: .me) else { return XCTFail("should play") }
            clock.advance(1)
        }
        guard case .paused(let until) = exchange.send(.psst, from: .me) else {
            return XCTFail("burst should pause")
        }
        XCTAssertEqual(exchange.status(for: .me), .paused(until: until))
        XCTAssertEqual(exchange.events.count, LocalExchange.burstLimit)

        clock.advance(LocalExchange.pauseDuration + 1)
        guard case .played = exchange.send(.psst, from: .me) else { return XCTFail("should resume") }
    }

    func testPauseAppliesOnlyToTheSender() {
        let exchange = makeExchange()
        for _ in 0...LocalExchange.burstLimit {
            exchange.send(.psst, from: .me)
            clock.advance(1)
        }
        XCTAssertNotNil(exchange.activePause(for: .me))
        guard case .played = exchange.send(.psst, from: .alex) else { return XCTFail("Alex unaffected") }
    }

    func testReceiptIsOnlyClaimedAfterTheOtherScreenShowsIt() {
        let exchange = makeExchange()
        exchange.send(.psst, from: .me)
        XCTAssertEqual(exchange.status(for: .me), .playedLocally(.psst))

        exchange.markSeen(by: .me) // opening your own screen proves nothing about Alex's
        XCTAssertEqual(exchange.status(for: .me), .playedLocally(.psst))

        exchange.markSeen(by: .alex)
        XCTAssertEqual(exchange.status(for: .me), .shownToOther(.psst))
    }

    func testAlexTapsBackWithWhatTheyReceived() {
        let exchange = makeExchange()
        exchange.send(.psst, from: .me)
        XCTAssertEqual(exchange.status(for: .alex), .received(.psst))

        clock.advance(1)
        exchange.send(exchange.tapSignal(for: .alex), from: .alex)
        XCTAssertEqual(exchange.status(for: .me), .received(.psst))
        XCTAssertEqual(exchange.unseenEvents(to: .me).count, 1)
        XCTAssertEqual(exchange.status(for: .alex), .playedLocally(.psst))

        exchange.markSeen(by: .me)
        XCTAssertTrue(exchange.unseenEvents(to: .me).isEmpty)
        XCTAssertEqual(exchange.status(for: .alex), .shownToOther(.psst))
    }

    func testSendingAgainReplacesReceivedStatus() {
        let exchange = makeExchange()
        exchange.send(.psst, from: .alex)
        XCTAssertEqual(exchange.status(for: .me), .received(.psst))
        exchange.send(.psst, from: .me)
        XCTAssertEqual(exchange.status(for: .me), .playedLocally(.psst))
    }

    func testRetainedHistoryIsBounded() {
        let exchange = makeExchange()
        for index in 0..<(LocalExchange.retainedEvents + 10) {
            exchange.send(.psst, from: index.isMultiple(of: 2) ? .me : .alex)
            clock.advance(LocalExchange.burstWindow)
        }
        XCTAssertEqual(exchange.events.count, LocalExchange.retainedEvents)
    }
}
