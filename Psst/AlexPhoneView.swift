import SwiftUI

struct AlexPhoneView: View {
    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var incomingEffect: EffectTrigger?
    @State private var replyEffect: EffectTrigger?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 52
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
                            .font(.body.weight(.semibold)).frame(minHeight: 48)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text("ALEX’S SIDE").font(.footnote.weight(.semibold)).tracking(1)
                }.foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 12)
                ScrollView {
                    VStack(spacing: 0) {
                        if let event = exchange.latestEvent(to: .alex) {
                            VStack(spacing: 22) {
                                Text("FROM YOU").font(.subheadline.weight(.semibold)).tracking(2)
                                SignalGlyph(signal: event.signal, trigger: incomingEffect?.id, baseSize: 64, tint: .white)
                                    .frame(height: 90)
                                Text(event.signal.title.uppercased())
                                    .bandTitle(event.signal.title, size: titleSize, tracking: -1.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(event.signal.meaning).font(.body)
                            }.multilineTextAlignment(.center).foregroundStyle(.white)
                                .padding(24).frame(maxWidth: .infinity, minHeight: max(300, proxy.size.height * 0.50))
                                .background(event.signal.accent).accessibilityElement(children: .combine)
                        } else {
                            Text("Nothing from you yet.")
                                .font(.title2.weight(.semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 220).padding(24)
                        }
                        PersonRow(name: "You", status: replyStatusText,
                                  signal: exchange.tapSignal(for: .alex), effect: replyEffect,
                                  accessibilityHint: "Plays \(exchange.tapSignal(for: .alex).title) back in the local demo.",
                                  action: tapBack)
                        Text("Local demo. Nothing leaves this phone.")
                            .font(.footnote).foregroundStyle(Color.onCanvasSecondary).padding(24)
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
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
        incomingEffect = EffectTrigger(id: latest.id, signal: latest.signal)
    }
    private func tapBack() {
        switch exchange.send(exchange.tapSignal(for: .alex), from: .alex) {
        case .played(let event): replyEffect = EffectTrigger(id: event.id, signal: event.signal)
        case .paused: AccessibilityNotification.Announcement("Paused for a moment after several taps").post()
        case .tooSoon, .alreadyRecorded: break
        }
    }
}
