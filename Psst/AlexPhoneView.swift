import SwiftUI

struct AlexPhoneView: View {
    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrival: Arrival?
    @State private var replyEffect: EffectTrigger?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Stacks at accessibility sizes so "Your phone" never breaks mid-word.
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.xs))
                    : AnyLayout(HStackLayout())) {
                    Button { dismiss() } label: {
                        Label("Your phone", systemImage: "arrow.left")
                            .font(.psst(.body, weight: .semibold)).frame(minHeight: Tokens.Band.headerControlHeight)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text("LOCAL DEMO · ALEX’S SIDE").font(.psst(.footnote, weight: .semibold)).tracking(Tokens.Band.labelTracking)
                }.foregroundStyle(.white).padding(.horizontal, Tokens.Space.xl).padding(.vertical, Tokens.Space.m)
                // DM2: Alex's side receives exactly like the real app (R2).
                if let arrival {
                    ArrivalView(arrival: arrival,
                                onTap: { withAnimation { self.arrival = nil }; tapBack() },
                                onDone: { withAnimation { self.arrival = nil } })
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if exchange.latestEvent(to: .alex) == nil {
                                Text("Nothing from you yet.")
                                    .font(.psst(.title2, weight: .semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 220).padding(Tokens.Space.xl)
                            }
                            PersonRow(name: "You", status: replyStatusText,
                                      signal: exchange.tapSignal(for: .alex), effect: replyEffect,
                                      accessibilityHint: "Plays a Psst back in the local demo.",
                                      action: tapBack,
                                      minHeight: max(Tokens.personRowMinHeight, proxy.size.height * 0.5))
                            Text("Local demo. Nothing leaves this phone.")
                                .font(.psst(.footnote)).foregroundStyle(Color.onCanvasSecondary).padding(Tokens.Space.xl)
                        }
                    }
                }
            }
        }.background(Color.psstCanvas.ignoresSafeArea()).preferredColorScheme(.dark)
            .sensoryFeedback(trigger: replyEffect) { _, new in new?.signal.haptic }
            .task { await revealIncoming() }
    }
    private var replyStatusText: String {
        switch exchange.status(for: .alex) {
        case .ready(let signal), .received(let signal): "Tap to \(signal.title.lowercased()) back"
        case .playedLocally(let signal): "\(signal.title) back · played locally"
        case .shownToOther(let signal): "\(signal.title) back · seen in demo"
        case .paused: "Paused briefly. Try again shortly."
        }
    }
    private func revealIncoming() async {
        guard let latest = exchange.unseenEvents(to: .alex).last else { return }
        exchange.markSeen(by: .alex)
        arrival = Arrival(id: latest.id, connectionID: nil, senderName: "You")
    }
    private func tapBack() {
        switch exchange.send(exchange.tapSignal(for: .alex), from: .alex) {
        case .played(let event): replyEffect = EffectTrigger(id: event.id, signal: event.signal)
        case .paused: AccessibilityNotification.Announcement("Paused for a moment after several taps").post()
        case .tooSoon, .alreadyRecorded: break
        }
    }
}
