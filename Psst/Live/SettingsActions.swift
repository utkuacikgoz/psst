import Foundation
import Observation

/// Keeps destructive-looking rows visible until the server confirms the action.
@MainActor @Observable
final class SettingsActions {
    var openInvites: [OpenInvite] = []
    var blocked: [BlockedPerson] = []
    private(set) var loadingLists = false
    private(set) var listsLoaded = false
    private(set) var blockedLoadFailed = false
    private(set) var invitesLoadFailed = false

    func load(api: any PsstAPI) async {
        guard !loadingLists else { return }
        loadingLists = true
        defer { loadingLists = false; listsLoaded = true }
        async let people: Void = loadBlocked(api: api)
        async let invites: Void = loadInvites(api: api)
        _ = await (people, invites)
    }

    private func loadBlocked(api: any PsstAPI) async {
        do { blocked = try await api.listBlocked(); blockedLoadFailed = false }
        catch { blockedLoadFailed = true }
    }

    private func loadInvites(api: any PsstAPI) async {
        do { openInvites = try await api.listOpenInvites(); invitesLoadFailed = false }
        catch { invitesLoadFailed = true }
    }

    private(set) var revoking: Set<String> = []
    private(set) var unblocking: Set<UUID> = []
    private(set) var isRenaming = false
    private(set) var inviteError: String?
    private(set) var unblockError: String?
    private(set) var nameMessage: String?

    func rename(to draft: String, api: any PsstAPI, save: ((String) async throws -> Void)? = nil) async -> Bool {
        guard !isRenaming else { return false }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count) else {
            nameMessage = "Names can be 1 to 40 characters."
            return false
        }
        isRenaming = true
        nameMessage = nil
        defer { isRenaming = false }
        do {
            if let save { try await save(name) } else { try await api.setDisplayName(name) }
            nameMessage = "Saved. People you're connected with now see \(name)."
            return true
        } catch APIError.offline {
            nameMessage = "You're offline. Your name hasn't changed. Try again once you're back online."
        } catch {
            nameMessage = "Couldn't save your name. Try again."
        }
        return false
    }

    func revoke(_ invite: OpenInvite, api: any PsstAPI) async {
        guard !revoking.contains(invite.code) else { return }
        revoking.insert(invite.code)
        inviteError = nil
        defer { revoking.remove(invite.code) }
        do {
            try await api.revokeInvite(code: invite.code)
            openInvites.removeAll { $0.code == invite.code }
        } catch {
            inviteError = "Couldn't cancel \(invite.displayCode). It may still work. Try Cancel again."
        }
    }

    func unblock(_ person: BlockedPerson, api: any PsstAPI) async {
        guard !unblocking.contains(person.userId) else { return }
        unblocking.insert(person.userId)
        unblockError = nil
        defer { unblocking.remove(person.userId) }
        do {
            try await api.unblockUser(person.userId)
            blocked.removeAll { $0.userId == person.userId }
        } catch {
            unblockError = "Couldn't unblock \(person.displayName). Try Unblock again."
        }
    }
}
