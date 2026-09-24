import SwiftUI

/// A simulated view of what Alex would see, shown on this same device.
struct AlexPhoneView: View {
    @Environment(LocalExchange.self) private var exchange
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var incomingEffect: EffectTrigger?
    @State private var replyEffect: EffectTrigger?
    @ScaledMetric(relativeTo: .title2) private var signalTitleSize: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let inset = Tokens.sideInset(forWidth: proxy.size.width)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Your phone", systemImage: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onCanvas)
                            .frame(minHeight: Tokens.minTouch)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                }
                .padding(.horizontal, inset)
                .padding(.top, Tokens.Space.s)

                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("Alex's phone")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Color.onCanvas)
                            .accessibilityAddTraits(.isHeader)
                        LocalPreviewNotice(text: "Simulated on this device. Nothing is sent or received.")
                            .padding(.bottom, Tokens.Space.s)

                        if let incoming = exchange.latestEvent(to: .alex) {
                            incomingCard(incoming)
                        } else {
                            Text("Nothing from you yet. Go back and tap Alex first.")
                                .font(.body)
                                .foregroundStyle(Color.onCanvas)
                                .padding(.vertical, Tokens.Space.l)
                        }

                        PersonRow(
                            name: "You",
                            status: replyStatusText,
                            signal: exchange.tapSignal(for: .alex),
                            effect: replyEffect,
                            accessibilityHint: "Plays \(exchange.tapSignal(for: .alex).title) back to you in the simulation.",
                            action: tapBack
                        )
                        .padding(.top, Tokens.Space.l)
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, Tokens.Space.l)
                }
            }
        }
        .background(Color.psstCanvas.ignoresSafeArea())
        .sensoryFeedback(trigger: replyEffect) { _, new in new?.signal.haptic }
        .task { await revealIncoming() }
    }

    /// Sender first, then the effect.
    private func incomingCard(_ event: SignalEvent) -> some View {
        let earlier = max(0, exchange.events.filter { $0.to == .alex }.count - 1)

        return VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("From you")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)

            HStack(spacing: Tokens.Space.m) {
                SignalGlyph(signal: event.signal, trigger: incomingEffect?.id, baseSize: 36)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(event.signal.title)
                        .font(.system(size: signalTitleSize, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(event.signal.meaning)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            timeLine(for: event, earlier: earlier)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.controlRadius).fill(Color.surface))
        .accessibilityElement(children: .combine)
    }

    private func timeLine(for event: SignalEvent, earlier: Int) -> Text {
        let ago = Text("\(Text(event.createdAt, style: .relative)) ago")
        return earlier > 0 ? ago + Text(" · \(earlier) earlier") : ago
    }

    private var replyStatusText: String {
        switch exchange.status(for: .alex) {
        case .ready(let signal):
            "Tap to play \(signal.title)"
        case .received(let signal):
            "Tap to send \(signal.title) back"
        case .playedLocally(let signal):
            "\(signal.title) back · shows when you return to your phone"
        case .shownToOther(let signal):
            "\(signal.title) back · shown on your phone"
        case .paused:
            "Paused for a moment after several taps"
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
        case .played(let event):
            replyEffect = EffectTrigger(id: event.id, signal: event.signal)
        case .paused:
            AccessibilityNotification.Announcement("Paused for a moment after several taps").post()
        case .tooSoon, .alreadyRecorded:
            break
        }
    }
}
