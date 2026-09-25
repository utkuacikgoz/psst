import Foundation

struct ConnectionSummary: Decodable, Identifiable, Equatable {
    let connectionId: UUID
    let otherId: UUID
    let otherName: String
    let lastEventId: UUID?
    let lastFromMe: Bool?
    let lastEffect: String?
    let lastCreatedAt: Date?
    let lastSeenAt: Date?
    let unseenCount: Int

    var id: UUID { connectionId }
    var lastSignal: Signal? { lastEffect.flatMap(Signal.init(rawValue:)) }
}

struct UnseenSignal: Decodable, Identifiable, Equatable {
    let id: UUID
    let connectionId: UUID
    let senderId: UUID
    let senderName: String
    let effectId: String
    let createdAt: Date
    /// Both people pssted within 10 seconds, by the server's clock.
    var sameMoment: Bool? = nil

    var signal: Signal { Signal(rawValue: effectId) ?? .psst }
}

struct SendResult: Decodable, Equatable {
    let id: UUID
    let createdAt: Date
    let pushStatus: String
    let duplicate: Bool
    /// This send answered theirs within 10 seconds, by the server's clock.
    var sameMoment: Bool? = nil
}

struct CreatedInvite: Decodable, Equatable {
    let code: String
    let expiresAt: Date

    /// A web link, so it works for people who don't have Psst yet: with the app
    /// installed it opens the app (universal link); without, a page on
    /// psstapp.fun shows the code and where to get Psst.
    var link: URL { URL(string: "https://\(InviteLink.webHost)/invite/\(code)")! }
    /// "ABCD EFGH" for reading aloud or typing.
    var displayCode: String { code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code }
}

/// One of your own invites nobody has used yet (Settings → Open invites).
struct OpenInvite: Decodable, Identifiable, Equatable {
    let code: String
    let createdAt: Date
    let expiresAt: Date

    var id: String { code }
    var displayCode: String { code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code }
}

struct InvitePreview: Decodable, Equatable {
    enum Status: String, Decodable {
        case pending, own, used, revoked, expired, invalid
        case alreadyConnected = "already_connected"
    }
    let status: Status
    let inviterName: String?
}

struct AcceptedInvite: Decodable, Equatable {
    let status: String
    let connectionId: UUID?
}

struct BlockedPerson: Decodable, Identifiable, Equatable {
    let userId: UUID
    let displayName: String
    let blockedAt: Date

    var id: UUID { userId }
}

/// The routing data carried in a push payload's "psst" dictionary.
struct SignalPayload: Equatable {
    let eventID: UUID
    let connectionID: UUID
    let signal: Signal
    var sameMoment = false

    init(eventID: UUID, connectionID: UUID, signal: Signal, sameMoment: Bool = false) {
        self.eventID = eventID
        self.connectionID = connectionID
        self.signal = signal
        self.sameMoment = sameMoment
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let psst = userInfo["psst"] as? [String: Any],
              let event = (psst["event_id"] as? String).flatMap(UUID.init(uuidString:)),
              let connection = (psst["connection_id"] as? String).flatMap(UUID.init(uuidString:)),
              let signal = (psst["effect_id"] as? String).flatMap(Signal.init(rawValue:))
        else { return nil }
        self.init(eventID: event, connectionID: connection, signal: signal,
                  sameMoment: psst["same_moment"] as? Bool ?? false)
    }
}

extension UUID {
    /// A stable ID for replying to `original`, so a repeated notification action
    /// can't send two replies.
    static func reply(to original: UUID) -> UUID {
        var bytes = original.uuid
        bytes.0 ^= 0x5A
        bytes.1 ^= 0xC3
        bytes.15 ^= 0x3C
        return UUID(uuid: bytes)
    }
}

enum InviteLink {
    static let webHost = "psstapp.fun"

    /// Reads the code from https://psstapp.fun/invite/ABCDEFGH (a universal link)
    /// or the older psst://invite/ABCDEFGH.
    static func code(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased(), host = url.host?.lowercased()
        var parts = url.pathComponents.filter { $0 != "/" }
        if scheme == "psst", host == "invite" {
            // psst://invite/CODE: the code is the whole path.
        } else if scheme == "https", host == webHost || host == "www.\(webHost)", parts.first?.lowercased() == "invite" {
            parts.removeFirst()
        } else {
            return nil
        }
        let code = parts.first?
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard let code, !code.isEmpty else { return nil }
        return code
    }
}
