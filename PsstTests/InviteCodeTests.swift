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

    /// "I have a code" takes a pasted Psst link (/p/) or message as well (1.0.9 audit).
    func testPastedPsstLinksAndMessagesGiveTheCode() {
        XCTAssertEqual(InviteSheet.inviteCode(in: "https://psstapp.fun/p/ab12cd34"), "AB12CD34")
        XCTAssertEqual(InviteSheet.inviteCode(in: "Utku pssted you · 1 Psst waiting https://psstapp.fun/p/AB12CD34"), "AB12CD34")
        XCTAssertEqual(InviteSheet.inviteCode(in: "psst://invite/K7QX4MPA"), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "(code K7QX 4MPA)"), "K7QX4MPA")
        XCTAssertEqual(InviteLink.code(inPasted: "https://psstapp.fun/p/AB12CD34"), "AB12CD34")
        XCTAssertNil(InviteLink.code(linkedIn: "no link here"))
    }
}
