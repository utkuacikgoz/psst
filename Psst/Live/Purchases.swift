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
    private(set) var state: State = .idle
    private(set) var loadFailed = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
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

    func buy() async {
        guard let product, state != .purchasing else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
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
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            state = .failed("Couldn't reach the App Store. Try again in a moment.")
        }
        await refreshEntitlement()
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
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.grants(productID: transaction.productID, revocationDate: transaction.revocationDate) {
                unlocked = true
            }
        }
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

    /// The eight band colours on offer (BC1), the default palette first.
    static let palette: [UInt32] = [0x5F61AE, 0xAC3E68, 0x2476AA, 0x187F69, 0xB34F2B, 0x8A6500, 0x2B2B38, 0xC2185B]

    /// Alternate app icons: display name and asset name (nil is the default).
    static let icons: [(title: String, name: String?, preview: UInt32)] = [
        ("Purple", nil, 0x713F93), ("Night", "AppIcon-Night", 0x1C1726),
        ("Gold", "AppIcon-Gold", 0xB87500), ("Pink", "AppIcon-Pink", 0xAC3E68),
    ]

    private(set) var colors: [UUID: UInt32]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.colorsKey) as? [String: Int] ?? [:]
        colors = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UUID(uuidString: key).map { ($0, UInt32(truncatingIfNeeded: value)) }
        })
    }

    /// Someone's band colour: your choice if you made one, else the usual one.
    func color(for id: UUID, name: String) -> Color {
        colors[id].map { Color(hex: $0) } ?? .personBand(name)
    }

    func setColor(_ hex: UInt32?, for id: UUID) {
        colors[id] = hex
        defaults.set(Dictionary(uniqueKeysWithValues: colors.map { ($0.key.uuidString, Int($0.value)) }),
                     forKey: Self.colorsKey)
    }
}
