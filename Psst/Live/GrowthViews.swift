import SwiftUI
import UserNotifications

// 1.0.9 picks (owner, 10 Nov 2026): the one-time widget tip and "New in Psst" (4A),
// the streak saver offer (5A) and the Share my week story card (14A).

/// 4A: once, after your first two-way Psst, in the first tip's dark style, with a
/// small picture of that person's widget. Any tap closes it; nothing is sent.
struct WidgetTipOverlay: View {
    let name: String
    let line: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            // Scrolls at the largest text sizes instead of clipping.
            ScrollView {
                VStack(spacing: Tokens.Space.l) {
                    miniWidget
                    Text("Put \(name) on your Home Screen")
                        .font(.psst(.title2, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free. Touch and hold your Home Screen, tap Edit, then Add Widget and pick Psst.")
                        .font(.psst(.body, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap anywhere to close")
                        .font(.psst(.footnote, weight: .semibold))
                        .foregroundStyle(Color.onCanvasSecondary)
                        .padding(.top, Tokens.Space.l)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.onCanvas)
                .padding(Tokens.Space.xl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.black.opacity(0.8).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tip: put \(name) on your Home Screen. Free. Touch and hold your Home Screen, tap Edit, then Add Widget and pick Psst.")
        .accessibilityHint("Dismisses the tip.")
        .accessibilityAddTraits([.isButton, .isModal])
        .accessibilityAction { onDismiss() }
    }

    /// Their small widget as it would look: their band, their name, when they last pssted you.
    private var miniWidget: some View {
        VStack(spacing: 2) {
            Text(name.uppercased())
                .font(.psst(size: 26, weight: .black))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(line)
                .font(.psst(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.onCanvas)
        .padding(Tokens.Space.s)
        .frame(width: 104, height: 104)
        .background(color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// 4A: "New in Psst", once, for people who had Psst before this version.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    Text("New in Psst")
                        .font(.psst(size: titleSize, weight: .black))
                        .tracking(Tokens.Band.titleTracking)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Tokens.Space.s)
                    item("Your #1 person on your Home Screen",
                         "Free: when they last pssted you and your streak. Touch and hold your Home Screen to add it.")
                    // Psst+ › Redeem a code sits under Restore purchase (8A, 20 Oct 2026).
                    item("Redeem a code", "Got a Psst+ code? It's in Psst+ under Restore.")
                }
                .foregroundStyle(Color.ink)
                .padding(Tokens.sheetInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button { dismiss() } label: {
                Text("Got it")
                    .font(.psst(.body, weight: .bold))
                    .foregroundStyle(Color.onCanvas)
                    .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                    .background(Color.psstCanvas)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color.surface.ignoresSafeArea())
        .presentationBackground(Color.surface)
    }

    private func item(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title)
                .font(.psst(.headline, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.psst(.subheadline, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 5A: offered once, the first time a streak reaches 3. REMIND ME asks iOS for
/// notifications if needed and turns the 8 PM reminder on; it's off otherwise.
struct StreakSaverSheet: View {
    let name: String
    let onDone: () -> Void

    @Environment(LiveStore.self) private var store
    @State private var saving = false
    @State private var failed = false
    /// As tall as what it shows; scrolls if that's more than the screen (large text).
    @State private var contentHeight: CGFloat = 320
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.l) {
                Text("Keep it going?")
                    .font(.psst(.title2, weight: .black))
                    .foregroundStyle(Color.psstCanvas)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Get one reminder at 8 PM if your streak with \(name) is about to go out. Never more than one a day.")
                    .font(.psst(.subheadline, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text("Couldn't turn it on. Try again.")
                        .font(.psst(.footnote, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: remind) {
                    ZStack {
                        Text("REMIND ME").opacity(saving ? 0 : 1)
                        if saving { ProgressView().tint(Color.onCanvas) }
                    }
                    .font(.psst(.body, weight: .black))
                    .tracking(Tokens.Band.labelTracking)
                    .foregroundStyle(Color.onCanvas)
                    .frame(maxWidth: .infinity, minHeight: Tokens.minTouch + Tokens.Space.s)
                    .background(Color.psstCanvas, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .accessibilityLabel("Remind me")
                Button("No thanks", action: onDone)
                    .font(.psst(.body, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minHeight: Tokens.minTouch)
                    .disabled(saving)
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .presentationDetents([.height(contentHeight + bottomInset)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.white)
    }

    private func remind() {
        guard !saving else { return }
        saving = true
        failed = false
        Task {
            await SettingsSheet.allowNotificationsIfNeeded()
            if await store.setStreakReminders(true) {
                onDone()
            } else {
                failed = true
                AccessibilityNotification.Announcement("Couldn't turn it on. Try again.").post()
            }
            saving = false
        }
    }
}

/// 14A: the 9:16 story card SHARE MY WEEK shares. Your #1 is an initial only, never
/// a full name.
struct ShareWeekCard: View {
    let total: Int
    let initial: String?
    let streakDays: Int?

    /// Where the card points friends (the site's ct= campaign style).
    static let link = URL(string: "https://psstapp.fun/?ct=share-week")!

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("MY WEEK ON PSST")
                .font(.psst(size: 15, weight: .bold))
                .tracking(2)
            Text("\(total)")
                .font(.psst(size: 96, weight: .black))
                .tracking(-3)
            Text(verbatim: total == 1 ? "Psst" : "Pssts")
                .font(.psst(size: 20, weight: .bold))
            if let initial {
                Text("MY #1")
                    .font(.psst(size: 15, weight: .bold))
                    .tracking(2)
                    .padding(.top, 18)
                Text(verbatim: initial)
                    .font(.psst(size: 56, weight: .black))
                if let streakDays {
                    Text(verbatim: streakDays == 1 ? "🔥 1 day" : "🔥 \(streakDays) days")
                        .font(.psst(size: 18, weight: .bold))
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "psstapp.fun")
                .font(.psst(size: 26, weight: .black))
                .padding(.bottom, 56)
        }
        .foregroundStyle(Color.onCanvas)
        .multilineTextAlignment(.center)
        .frame(width: 360, height: 640)
        .background(Color.psstCanvas)
    }

    /// "K." from "Kim": the first letter only.
    static func initial(of name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() + "." }
    }

    /// The streak shown under your #1: only one that is with your #1 (never someone
    /// else's next to their initial), from 3 days like the band's flame.
    static func streakDays(for recap: WeeklyRecap, connections: [ConnectionSummary]) -> Int? {
        guard let top = recap.top else { return nil }
        if let streak = recap.streak, streak.connectionId == top.connectionId, streak.days >= 3 { return streak.days }
        if let days = connections.first(where: { $0.id == top.connectionId })?.streakDays, days >= 3 { return days }
        return nil
    }

    /// 1080 × 1920, for Stories and Messages.
    @MainActor static func image(for recap: WeeklyRecap, connections: [ConnectionSummary]) -> UIImage? {
        let card = ShareWeekCard(total: recap.total,
                                 initial: recap.top.flatMap { initial(of: $0.name) },
                                 streakDays: streakDays(for: recap, connections: connections))
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }
}
