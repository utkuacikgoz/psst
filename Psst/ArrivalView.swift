import SwiftUI

/// A full-screen moment: a Psst that just arrived (R2), someone new (J2), or
/// both of you pssting within 10 seconds by the server's clock (X2).
struct Arrival: Identifiable, Equatable {
    enum Kind { case signal, joined, sameMoment }

    /// The signal event (or, for a welcome, the connection), so it never shows twice.
    let id: UUID
    let connectionID: UUID?
    let senderName: String
    var kind: Kind = .signal
    /// MA2: when several people pssted, each gets a moment; "2 of 3".
    var position: Int? = nil
    var total: Int? = nil
}

/// The person's colour fills the screen for a moment, then it settles back
/// into the list. Tapping a Psst or a welcome sends one; tapping a same moment
/// just closes it.
struct ArrivalView: View {
    let arrival: Arrival
    let onTap: () -> Void
    let onDone: () -> Void
    /// The sender's band colour, if you chose one with Psst+.
    var color: Color? = nil

    static let displayTime: Duration = .milliseconds(1800)
    static let sameMomentTime: Duration = .milliseconds(2600)
    /// Each moment in a sequence is shorter, so three people don't take all day.
    static let queuedTime: Duration = .milliseconds(1400)

    private var holdTime: Duration {
        #if DEBUG
        // App Store screenshot runs hold each moment so it can be captured.
        if ProcessInfo.processInfo.arguments.contains("-PsstUITestHoldMoments") { return .seconds(8) }
        #endif
        if arrival.kind == .sameMoment { return Self.sameMomentTime }
        return arrival.total == nil ? Self.displayTime : Self.queuedTime
    }

    private var countPrefix: String {
        guard let position = arrival.position, let total = arrival.total else { return "" }
        return "\(position) of \(total) · "
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 70
    @ScaledMetric(relativeTo: .largeTitle) private var psstSize: CGFloat = Tokens.Band.titleSize
    @ScaledMetric(relativeTo: .title) private var labelSize: CGFloat = 26
    @State private var trigger: UUID?

    private var name: String { arrival.senderName }

    private var announcement: String {
        switch arrival.kind {
        case .signal: "\(countPrefix)Psst from \(name)"
        case .joined: "\(name) is in. You're connected."
        case .sameMoment: "Same moment. You and \(name) pssted each other at the same time."
        }
    }

    private var hint: String {
        switch arrival.kind {
        case .signal: "Sends a Psst back."
        case .joined: "Sends your first Psst."
        case .sameMoment: "Closes."
        }
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if arrival.kind == .sameMoment { sameMoment } else { single }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(arrival.kind == .sameMoment ? .success : .impact(flexibility: .soft), trigger: trigger)
        .task(id: arrival.id) {
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 150))
            trigger = arrival.id
            try? await Task.sleep(for: holdTime)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }

    private var single: some View {
        VStack(spacing: Tokens.Space.l) {
            if arrival.kind == .signal {
                Text("FROM")
                    .font(.psst(.subheadline, weight: .bold))
                    .tracking(Tokens.Band.labelTracking * 2)
            }
            Text(name.uppercased())
                .bandTitle(name, size: nameSize, tracking: Tokens.Band.titleTracking)
                .fixedSize(horizontal: false, vertical: true)
            if arrival.kind == .signal {
                SignalGlyph(signal: .psst, trigger: trigger, baseSize: psstSize, tint: .white)
                Text("Psst!")
                    .font(.psst(size: psstSize * 0.8, weight: .heavy))
                    .opacity(0.9)
            } else {
                Text("IS IN")
                    .font(.psst(size: psstSize * 0.8, weight: .heavy))
                    .tracking(Tokens.Band.titleTracking)
                    .opacity(0.9)
            }
            Text(arrival.kind == .signal ? "\(countPrefix)Tap to psst back" : "Tap to send your first Psst")
                .font(.psst(.subheadline, weight: .medium))
                .padding(.top, Tokens.Space.l)
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((color ?? .personBand(name)).ignoresSafeArea())
    }

    /// Your half (the app's purple) above theirs, with SAME MOMENT across the seam.
    private var sameMoment: some View {
        VStack(spacing: 0) {
            half("You", color: .psstCanvas)
            half(name, color: color ?? .personBand(name))
        }
        .overlay {
            Text("SAME MOMENT")
                .font(.psst(size: labelSize, weight: .heavy))
                .tracking(Tokens.Band.titleTracking / 2)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
                .background(Color.surface)
                .scaleEffect(trigger == nil || reduceMotion ? 1 : 1.06)
                .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.5), value: trigger)
                .padding(.horizontal, Tokens.Space.xl)
        }
    }

    private func half(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .bandTitle(title, size: nameSize * 0.75, tracking: Tokens.Band.titleTracking)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.ignoresSafeArea())
    }
}
