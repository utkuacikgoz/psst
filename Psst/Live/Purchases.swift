import StoreKit
import SwiftUI

/// Psst+ (owner decision): one optional, non-consumable unlock with personal
/// extras only. Sending, receiving, Psst back and invites never depend on it.
///
/// The entitlement comes only from StoreKit's verified transactions, re-read at
/// launch and whenever a transaction changes (purchase on another device,
/// Ask to Buy approval, refund or revocation).
@MainActor
@Observable
final class Purchases {
    nonisolated static let productID = "psstplus.unlock"

    enum State: Equatable {
        case idle
        case purchasing
        /// Ask to Buy or a payment that needs attention; it finishes later.
        case pending
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var isUnlocked = false
    private(set) var signedTransaction: String?
    private(set) var state: State = .idle
    private(set) var loadFailed = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    /// The price to show: the App Store's, or a sample in screenshot runs.
    var displayPrice: String? { product?.displayPrice ?? Self.sampleUITestPrice }

    #if DEBUG
    /// Screenshot runs have no App Store connection: -PsstUITestPlusPrice shows
    /// a sample price, and -PsstUITestPlusUnlocked shows the unlocked sheet.
    private static let sampleUITestPrice: String? =
        ProcessInfo.processInfo.arguments.contains("-PsstUITestPlusPrice") ? "$2.99" : nil
    private static let uiTestUnlocked = ProcessInfo.processInfo.arguments.contains("-PsstUITestPlusUnlocked")
    #else
    private static let sampleUITestPrice: String? = nil
    private static let uiTestUnlocked = false
    #endif

    init() {
        if Self.uiTestUnlocked {
            isUnlocked = true
            return
        }
        updates = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await load() }
    }

    func load() async {
        loadFailed = false
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { loadFailed = true }
        } catch {
            loadFailed = true
        }
        await refreshEntitlement()
    }

    func buy(accountID: UUID? = nil) async {
        guard let product, state != .purchasing else { return }
        state = .purchasing
        do {
            switch try await product.purchase(options: accountID.map { [.appAccountToken($0)] } ?? []) {
            case .success(let result):
                await handle(result)
                state = .idle
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed("The purchase didn't go through. You haven't been charged.")
        }
    }

    /// Restore purchase: asks the App Store to sync, then re-reads entitlements.
    /// Returns false when the App Store couldn't be reached (the reason is in `state`).
    @discardableResult
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            state = .failed("Couldn't reach the App Store. Try again in a moment.")
            await refreshEntitlement()
            return false
        }
        await refreshEntitlement()
        return true
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        // Unverified transactions never unlock anything.
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var unlocked = false
        var proof: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.grants(productID: transaction.productID, revocationDate: transaction.revocationDate) {
                unlocked = true
                proof = result.jwsRepresentation
            }
        }
        signedTransaction = proof
        isUnlocked = unlocked
        if unlocked, case .pending = state { state = .idle }
    }

    /// A refunded or revoked purchase stops unlocking.
    nonisolated static func grants(productID: String, revocationDate: Date?) -> Bool {
        productID == Self.productID && revocationDate == nil
    }
}

/// Personal Psst+ choices. They live on this phone only; nobody else sees them.
@MainActor
@Observable
final class Personalization {
    static let colorsKey = "psst.plus.bandColors"
    static let slotsKey = "psst.usualBandSlots"

    /// The band colours on offer (BC1), the default palette first. All keep
    /// white names readable (3:1 or better for band-size text).
    static let palette: [UInt32] = [0x5F61AE, 0xAC3E68, 0x2476AA, 0x187F69, 0xB34F2B, 0x8A6500, 0x2B2B38, 0xC2185B,
                                    0x1F4E8C, 0x2E6B3A, 0x0E6E78, 0xA22B3A]
    /// What VoiceOver calls each palette colour.
    static let colourNames: [UInt32: String] = [
        0x5F61AE: "Indigo", 0xAC3E68: "Rose", 0x2476AA: "Blue", 0x187F69: "Emerald",
        0xB34F2B: "Rust", 0x8A6500: "Ochre", 0x2B2B38: "Charcoal", 0xC2185B: "Raspberry",
        0x1F4E8C: "Navy", 0x2E6B3A: "Forest", 0x0E6E78: "Teal", 0xA22B3A: "Crimson",
    ]

    /// Alternate app icons: display name and asset name (nil is the default).
    static let icons: [(title: String, name: String?, preview: UInt32)] = [
        ("Purple", nil, 0x713F93), ("Night", "AppIcon-Night", 0x1C1726),
        ("Mischief", "AppIcon-Cat", 0x713F93), ("Gold", "AppIcon-Gold", 0xB87500), ("Pink", "AppIcon-Pink", 0xAC3E68),
    ]

    private(set) var colors: [UUID: UInt32]
    /// Each person's usual colour, given in the order they joined so the first
    /// five people never share one (a name hash could match after two).
    private(set) var usualSlots: [UUID: Int]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let slots = defaults.dictionary(forKey: Self.slotsKey) as? [String: Int] ?? [:]
        usualSlots = Dictionary(uniqueKeysWithValues: slots.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        let stored = defaults.dictionary(forKey: Self.colorsKey) as? [String: Int] ?? [:]
        colors = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UUID(uuidString: key).map { ($0, UInt32(truncatingIfNeeded: value)) }
        })
    }

    /// Someone's band colour: your choice if you made one, else the usual one.
    func color(for id: UUID, name: String) -> Color {
        Color(hex: colorHex(for: id, name: name))
    }

    func colorHex(for id: UUID, name: String) -> UInt32 {
        if let chosen = colors[id] { return chosen }
        if let slot = usualSlots[id] { return Color.personBandPalette[slot % Color.personBandPalette.count] }
        return Color.personBandHex(name)
    }

    /// Gives anyone new a usual colour: the one their name always gave them if
    /// nobody else has it yet (so updating recolours no one needlessly), otherwise
    /// the least-used one among the people you have now.
    func assignUsualColors(to people: [(id: UUID, name: String)]) {
        let palette = Color.personBandPalette.count
        var counts = Array(repeating: 0, count: palette)
        for person in people { if let slot = usualSlots[person.id] { counts[slot % palette] += 1 } }
        var changed = false
        for person in people where usualSlots[person.id] == nil {
            let id = person.id
            let named = Color.personBandPalette.firstIndex(of: Color.personBandHex(person.name))
            let slot = named.flatMap { counts[$0] == 0 ? $0 : nil }
                ?? counts.indices.min { counts[$0] < counts[$1] } ?? 0
            usualSlots[id] = slot
            counts[slot] += 1
            changed = true
        }
        guard changed else { return }
        defaults.set(Dictionary(uniqueKeysWithValues: usualSlots.map { ($0.key.uuidString, $0.value) }),
                     forKey: Self.slotsKey)
    }

    /// Home's colours, top to bottom. A usual colour that would match the band above
    /// it moves to the next usual colour, so two neighbours never merge into one block.
    /// Colours you chose yourself are never changed.
    func bandColors(for people: [(id: UUID, name: String)]) -> [UUID: UInt32] {
        var result: [UUID: UInt32] = [:]
        var above: UInt32?
        for person in people {
            var hex = colorHex(for: person.id, name: person.name)
            if colors[person.id] == nil, hex == above {
                let palette = Color.personBandPalette
                let start = palette.firstIndex(of: hex) ?? 0
                hex = (1..<palette.count).map { palette[(start + $0) % palette.count] }.first { $0 != above } ?? hex
            }
            result[person.id] = hex
            above = hex
        }
        return result
    }

    func setColor(_ hex: UInt32?, for id: UUID) {
        colors[id] = hex
        defaults.set(Dictionary(uniqueKeysWithValues: colors.map { ($0.key.uuidString, Int($0.value)) }),
                     forKey: Self.colorsKey)
    }
}
