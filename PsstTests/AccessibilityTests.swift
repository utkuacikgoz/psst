import XCTest
@testable import Psst

final class AccessibilityTests: XCTestCase {
    /// VoiceOver reads a name for every colour on offer, never "Colour 3".
    func testEveryBandColourHasASpokenName() {
        for hex in Personalization.palette {
            XCTAssertNotNil(Personalization.colourNames[hex], String(hex, radix: 16))
        }
        XCTAssertEqual(Set(Personalization.colourNames.values).count, Personalization.palette.count)
    }
}

final class ExchangeLineTests: XCTestCase {
    func testOnlyWordsAreLowercasedAfterSent() {
        XCTAssertEqual(PersonRow.lowercasedStart("Just now"), "just now")
        XCTAssertEqual(PersonRow.lowercasedStart("Yesterday"), "yesterday")
        XCTAssertEqual(PersonRow.lowercasedStart("12m ago"), "12m ago")
        XCTAssertEqual(PersonRow.lowercasedStart("Oct 3"), "Oct 3")
    }
}

final class TransportErrorTests: XCTestCase {
    func testCancellationIsNotOffline() {
        XCTAssertEqual(APIClient.apiError(for: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(APIClient.apiError(for: CancellationError()), .cancelled)
        XCTAssertEqual(APIClient.apiError(for: URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(APIClient.apiError(for: URLError(.timedOut)), .offline)
    }

    func testCallsThatWouldDuplicateAreNeverRetried() {
        XCTAssertFalse(APIClient.isRetryable("rest/v1/rpc/create_invite"))
        XCTAssertFalse(APIClient.isRetryable("rest/v1/rpc/report_user"))
        XCTAssertTrue(APIClient.isRetryable("functions/v1/send-signal"))
        XCTAssertTrue(APIClient.isRetryable("rest/v1/rpc/list_connections"))
    }
}

final class SessionTests: XCTestCase {
    /// Only a session the server says is gone signs you out; anything else is temporary.
    func testOnlyAGoneSessionSignsOut() {
        XCTAssertTrue(APIClient.isDeadSession(status: 400, code: "refresh_token_not_found"))
        XCTAssertTrue(APIClient.isDeadSession(status: 400, code: "invalid_grant"))
        XCTAssertFalse(APIClient.isDeadSession(status: 429, code: "over_request_rate_limit"))
        XCTAssertFalse(APIClient.isDeadSession(status: 408, code: "unknown"))
        XCTAssertFalse(APIClient.isDeadSession(status: 400, code: "unknown"))
        XCTAssertFalse(APIClient.isDeadSession(status: 500, code: "invalid_grant"))
    }
}
