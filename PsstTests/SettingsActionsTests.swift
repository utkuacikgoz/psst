import XCTest
@testable import Psst

@MainActor
final class SettingsActionsTests: XCTestCase {
    private func invite() -> OpenInvite {
        OpenInvite(code: "ABCDEFGH", createdAt: Date(), expiresAt: Date().addingTimeInterval(3600))
    }

    func testFailedCancellationRetainsUsableInviteAndCanRetry() async {
        let api = FakeAPI(), actions = SettingsActions(), invite = invite()
        actions.openInvites = [invite]
        api.revokeError = APIError.offline
        await actions.revoke(invite, api: api)
        XCTAssertEqual(actions.openInvites, [invite])
        XCTAssertTrue(actions.inviteError?.contains("may still work") == true)
        XCTAssertTrue(actions.revoking.isEmpty)
        api.revokeError = nil
        await actions.revoke(invite, api: api)
        XCTAssertTrue(actions.openInvites.isEmpty)
        XCTAssertNil(actions.inviteError)
    }

    func testCancellationWaitsForConfirmationAndRejectsOverlappingRequest() async {
        let api = FakeAPI(), actions = SettingsActions(), invite = invite()
        actions.openInvites = [invite]; api.holdRevokes = true
        let request = Task { await actions.revoke(invite, api: api) }
        while api.pendingRevokeCount == 0 { await Task.yield() }
        XCTAssertEqual(actions.openInvites, [invite])
        XCTAssertTrue(actions.revoking.contains(invite.code))
        await actions.revoke(invite, api: api)
        XCTAssertEqual(api.revokedCodes, [invite.code])
        api.releaseRevoke(); await request.value
        XCTAssertTrue(actions.openInvites.isEmpty)
    }

    func testFailedUnblockRetainsPersonAndCanRetry() async {
        let api = FakeAPI(), actions = SettingsActions()
        let person = BlockedPerson(userId: UUID(), displayName: "Ada", blockedAt: Date())
        actions.blocked = [person]; api.unblockError = APIError.offline
        await actions.unblock(person, api: api)
        XCTAssertEqual(actions.blocked, [person]); XCTAssertNotNil(actions.unblockError)
        api.unblockError = nil
        await actions.unblock(person, api: api)
        XCTAssertTrue(actions.blocked.isEmpty); XCTAssertNil(actions.unblockError)
    }

    func testRenameValidatesLocallyAndDistinguishesRequestFailure() async {
        let api = FakeAPI(), actions = SettingsActions()
        let invalid = await actions.rename(to: String(repeating: "a", count: 41), api: api)
        XCTAssertFalse(invalid); XCTAssertTrue(api.renamedNames.isEmpty)
        XCTAssertEqual(actions.nameMessage, "Names can be 1 to 40 characters.")
        api.renameError = APIError.offline
        let offline = await actions.rename(to: "  Ada  ", api: api)
        XCTAssertFalse(offline); XCTAssertEqual(api.renamedNames, ["Ada"])
        XCTAssertTrue(actions.nameMessage?.contains("No internet") == true)
        api.renameError = APIError.server(status: 500, code: "server_error")
        let rejected = await actions.rename(to: "Ada", api: api)
        XCTAssertFalse(rejected); XCTAssertEqual(actions.nameMessage, "Couldn't save your name. Try again.")
        api.renameError = nil
        let saved = await actions.rename(to: "Ada", api: api)
        XCTAssertTrue(saved); XCTAssertTrue(actions.nameMessage?.hasPrefix("Saved.") == true)
    }
}
