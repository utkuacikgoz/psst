import SwiftUI

/// A Psst that just arrived, shown full screen for a moment (option R2).
struct Arrival: Identifiable, Equatable {
    enum Kind { case signal, joined }

    /// The signal event (or, for a welcome, the connection), so it never shows twice.
    let id: UUID
    let connectionID: UUID?
    let senderName: String
    var kind: Kind = .signal
}

/// The sender's colour fills the screen: who it's from first, then the Psst.
/// Tapping sends one back; otherwise it settles back into the list.
struct ArrivalView: View {
    let arrival: Arrival
    let onTap: () -> Void
    let onDone: () -> Void

    static let displayTime: Duration = .milliseconds(1800)

    private var announcement: String {
        arrival.kind == .signal ? "Psst from \(arrival.senderName)" : "\(arrival.senderName) is in. You're connected."
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 70
    @ScaledMetric(relativeTo: .largeTitle) private var psstSize: CGFloat = Tokens.Band.titleSize
    @State private var trigger: UUID?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Tokens.Space.l) {
                if arrival.kind == .signal {
                    Text("FROM")
                        .font(.subheadline.weight(.bold))
                        .tracking(Tokens.Band.labelTracking * 2)
                }
                Text(arrival.senderName.uppercased())
                    .bandTitle(arrival.senderName, size: nameSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                switch arrival.kind {
                case .signal:
                    SignalGlyph(signal: .psst, trigger: trigger, baseSize: psstSize, tint: .white)
                    Text("Psst!")
                        .font(.system(size: psstSize * 0.8, weight: .heavy))
                        .opacity(0.9)
                case .joined:
                    Text("IS IN")
                        .font(.system(size: psstSize * 0.8, weight: .heavy))
                        .tracking(Tokens.Band.titleTracking)
                        .opacity(0.9)
                }
                Text(arrival.kind == .signal ? "Tap to psst back" : "Tap to send your first Psst")
                    .font(.subheadline.weight(.medium))
                    .padding(.top, Tokens.Space.l)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.personBand(arrival.senderName).ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .accessibilityHint(arrival.kind == .signal ? "Sends a Psst back." : "Sends your first Psst.")
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: trigger)
        .task(id: arrival.id) {
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 150))
            trigger = arrival.id
            try? await Task.sleep(for: Self.displayTime)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}
