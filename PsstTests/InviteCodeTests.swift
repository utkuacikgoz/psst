import XCTest
@testable import Psst

@MainActor
final class InviteCodeTests: XCTestCase {
    func testPastedCodeIsFoundInLinksMessagesAndPlainCodes() {
        XCTAssertEqual(InviteSheet.inviteCode(in: "https://psstapp.fun/invite/K7QX4MPA"), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "https://psstapp.fun/invite/k7qx4mpa?x=1"), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "I want to be able to psst you. Tap to join me (code K7QX 4MPA)."), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "  k7qx 4mpa\n"), "K7QX4MPA")
    }
}
