import XCTest
@testable import Psst

@MainActor
final class InviteCodeTests: XCTestCase {
    func testPastedCodeIsFoundInLinksMessagesAndPlainCodes() {
        XCTAssertEqual(InviteSheet.inviteCode(in: "https://psstapp.fun/invite/K7QX4MPA"), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "https://psstapp.fun/invite/k7qx4mpa?x=1"), "K7QX4MPA")
        // 13A (10 Nov 2026): the group invite's message.
        XCTAssertEqual(InviteSheet.inviteCode(in: PsstShare.groupMessage(code: "K7QX4MPA")), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "Join our Psst? One tap says thinking of you. (code K7QX 4MPA)"), "K7QX4MPA")
        XCTAssertEqual(InviteSheet.inviteCode(in: "Join our Psst? One tap says thinking of you. (code K7QX4MPA) https://psstapp.fun/invite/K7QX4MPA"), "K7QX4MPA")
        // Messages from before 1.0.9 still paste.
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

    /// The day-5 reminder shares the link again with the message it first had (13A).
    func testReminderResharesWithTheLinksOwnMessage() {
        let doodle = PsstShare.resend(code: "AB12CD34", kind: "doodle")
        XCTAssertEqual(doodle?.items.first as? String, PsstShare.doodleMessage)
        XCTAssertEqual((doodle?.items.last as? URL)?.absoluteString, "https://psstapp.fun/p/AB12CD34")
        XCTAssertEqual(doodle?.isDoodle, true)
        XCTAssertEqual(PsstShare.resend(code: "AB12CD34", kind: "psst")?.items.first as? String, PsstShare.message)
        XCTAssertEqual(PsstShare.resend(code: "AB12CD34")?.items.first as? String, PsstShare.message, "older servers send no kind")
        let code = PsstShare.resend(code: "K7QX4MPA", kind: "code")
        XCTAssertEqual(code?.items.first as? String, "Join our Psst? One tap says thinking of you. (code K7QX4MPA)")
        XCTAssertEqual((code?.items.last as? URL)?.absoluteString, "https://psstapp.fun/invite/K7QX4MPA")
    }
}
