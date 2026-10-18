import Foundation

struct ConnectionSummary: Codable, Identifiable, Equatable {
    let connectionId: UUID
    let otherId: UUID
    let otherName: String
    let lastEventId: UUID?
    let lastFromMe: Bool?
    let lastEffect: String?
    let lastCreatedAt: Date?
    let lastSeenAt: Date?
    let unseenCount: Int
    /// Days in a row you've both pssted (3A); 0 or absent when there's no live streak.
    var streakDays: Int? = nil

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
    /// A doodle's strokes (effect "doodle").
    var doodle: DoodleStrokes? = nil
    /// The sender's Psst+ word for a plain Psst ("boop"); nil = "psst".
    var word: String? = nil

    var signal: Signal { Signal(rawValue: effectId) ?? .psst }
}

/// The newest doodle sent to you that you haven't answered: what the widget shows.
struct LatestDoodle: Codable, Equatable {
    let eventId: UUID
    let connectionId: UUID
    let senderName: String
    let createdAt: Date
    let doodle: DoodleStrokes
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
    /// How many people the code can join (10 since 13 Oct 2026); absent from older servers, so once.
    var maxUses: Int?

    /// "Works for up to 10 people", or "Works once" for a single-use code.
    var usesLine: String {
        let uses = maxUses ?? 1
        return uses > 1 ? "Works for up to \(uses) people" : "Works once"
    }

    /// A web link, so it works for people who don't have Psst yet: with the app
    /// installed it opens the app (universal link); without, a page on
    /// psstapp.fun shows the code and where to get Psst.
    /// "psst" for a Psst that is the invite (5A); its link says "Utku pssted you".
    var kind: String? = nil

    var link: URL { URL(string: "https://\(InviteLink.webHost)/\(kind == "psst" ? "p" : "invite")/\(code)")! }
    /// "ABCD EFGH" for reading aloud or typing.
    var displayCode: String { code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code }
}

/// Your open group code filling up (owner pick 1C, 15 Oct 2026): "3 of 10 joined",
/// who joined (only people still connected to you), and how long it has left.
struct InviteProgress: Decodable, Equatable {
    let code: String
    let expiresAt: Date
    let uses: Int
    let maxUses: Int
    let joined: [String]

    var invite: CreatedInvite { CreatedInvite(code: code, expiresAt: expiresAt, maxUses: maxUses) }

    /// "3 of 10 joined · 6 days left".
    func summary(now: Date = Date()) -> String {
        let days = max(1, Int((expiresAt.timeIntervalSince(now) / 86_400).rounded(.up)))
        return "\(uses) of \(maxUses) joined · \(days) \(days == 1 ? "day" : "days") left"
    }
}

/// One of your own invites nobody has used yet (Settings → Open invites).
struct OpenInvite: Decodable, Identifiable, Equatable {
    let code: String
    let createdAt: Date
    let expiresAt: Date
    /// "psst" for a Psst waiting for someone new (5A); absent or "code" otherwise.
    var kind: String? = nil

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
    /// They joined through a Psst that was the invite (5A): it arrives as their first.
    var heldPsst: Bool? = nil
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
    /// The sender's Psst+ word ("boop"), when they chose one.
    var word: String? = nil

    init(eventID: UUID, connectionID: UUID, signal: Signal, sameMoment: Bool = false, word: String? = nil) {
        self.eventID = eventID
        self.connectionID = connectionID
        self.signal = signal
        self.sameMoment = sameMoment
        self.word = word
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let psst = userInfo["psst"] as? [String: Any],
              let event = (psst["event_id"] as? String).flatMap(UUID.init(uuidString:)),
              let connection = (psst["connection_id"] as? String).flatMap(UUID.init(uuidString:)),
              let signal = (psst["effect_id"] as? String).flatMap(Signal.init(rawValue:))
        else { return nil }
        self.init(eventID: event, connectionID: connection,
                  signal: psst["super_psst"] as? Bool == true ? .superPsst
                      : psst["doodle"] as? Bool == true ? .doodle : signal,
                  sameMoment: psst["same_moment"] as? Bool ?? false,
                  word: PsstWord.shown(psst["word"] as? String))
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

    /// Reads the code from https://psstapp.fun/invite/ABCDEFGH or /p/ABCDEFGH (a Psst
    /// that is the invite; universal links) or the older psst://invite/ABCDEFGH.
    static func code(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased(), host = url.host?.lowercased()
        var parts = url.pathComponents.filter { $0 != "/" }
        if scheme == "psst", host == "invite" {
            // psst://invite/CODE: the code is the whole path.
        } else if scheme == "https", host == webHost || host == "www.\(webHost)",
                  ["invite", "p"].contains(parts.first?.lowercased() ?? "") {
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

    /// A code from pasted text: a whole message with a psstapp.fun link in it, a
    /// bare link, or just the code ("K7QX-4MPA"). nil when it doesn't look like one.
    static func code(inPasted text: String) -> String? {
        for word in text.split(whereSeparator: \.isWhitespace) {
            if let url = URL(string: String(word)), let code = code(from: url) { return code }
        }
        let bare = text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return (6...16).contains(bare.count) && text.count <= 24 ? bare : nil
    }
}


/// One person on your private leaderboard: all-time counts (kept as two numbers
/// per pair) and this month's (from the Pssts kept for 30 days).
struct ActivitySummary: Codable, Identifiable, Equatable {
    let connectionId: UUID
    let otherName: String
    let sentAll: Int
    let receivedAll: Int
    let sentMonth: Int
    let receivedMonth: Int
    var id: UUID { connectionId }
}

struct SuperAllowance: Decodable, Equatable {
    let remaining: Int
    let unlimited: Bool
    let resetsAt: Date
    let effectsEnabled: Bool
}

/// The oldest build allowed to connect and the newest one out (server app_config).
struct AppRequirements: Decodable, Equatable {
    let minBuild: Int
    let latestBuild: Int
    let latestVersion: String?
}

/// Your week, Monday to Sunday by your own calendar (weekly recap, owner pick 4A).
struct WeeklyRecap: Decodable, Equatable {
    struct Top: Decodable, Equatable {
        let connectionId: UUID
        let name: String
        let count: Int
        let still: Bool
    }
    struct Streak: Decodable, Equatable {
        let connectionId: UUID
        let name: String
        let days: Int
    }
    /// "2026-10-05": plain dates, not timestamps.
    let weekStart: String
    let weekEnd: String
    let total: Int
    let sent: Int
    let received: Int
    let top: Top?
    let streak: Streak?

    /// "Oct 5 – 11", or "Sep 29 – Oct 5" across months.
    var rangeLabel: String {
        let parse = Date.ISO8601FormatStyle().year().month().day()
        guard let start = try? Date(weekStart, strategy: parse), let end = try? Date(weekEnd, strategy: parse) else {
            return ""
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated)
        let day = Date.FormatStyle(timeZone: calendar.timeZone).day()
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        return "\(start.formatted(month)) \(start.formatted(day)) – " + (sameMonth ? "" : "\(end.formatted(month)) ") + end.formatted(day)
    }
}

struct WeeklyRecapStatus: Decodable, Equatable {
    let enabled: Bool
    let weekTotal: Int
}

/// Your word (owner picks 1A 2A 3A, 16 Oct 2026; Psst+): what the people you psst
/// see instead of "psst". A fixed list (the server checks the same one); the name
/// and the verb stay Psst.
enum PsstWord {
    static let all = ["psst", "hey", "boop", "oi", "yo", "hiii", "mwah", "psst psst"]

    /// A word from the list to show, or nil for plain "psst" (and anything unknown).
    static func shown(_ word: String?) -> String? {
        guard let word, word != "psst", all.contains(word) else { return nil }
        return word
    }
}
