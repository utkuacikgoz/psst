import SwiftUI

/// A full-screen moment: a Psst that just arrived (R2), someone new (J2), or
/// both of you pssting within 10 seconds by the server's clock (X2).
struct Arrival: Identifiable, Equatable {
    enum Kind { case signal, joined, sameMoment, superPsst }

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
    /// Rare, so it lingers a little longer.
    static let sameMomentTime: Duration = .milliseconds(3200)
    /// Each moment in a sequence is shorter, so three people don't take all day.
    static let queuedTime: Duration = .milliseconds(1400)

    private var holdTime: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PsstUITestLive") && ProcessInfo.processInfo.arguments.contains("superArrival") { return .seconds(30) }
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

    @AppStorage("psst.hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("psst.superEffectsEnabled") private var superEffectsEnabled = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title2) private var replySize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var psstSize: CGFloat = Tokens.Band.titleSize
    @ScaledMetric(relativeTo: .title) private var labelSize: CGFloat = 34
    @State private var trigger: UUID?

    private var name: String { arrival.senderName }

    /// People using VoiceOver, Switch Control or very large text need time to read
    /// and act, so the moment waits for them instead of closing on its own.
    private var staysOpen: Bool { voiceOver || switchControl || dynamicTypeSize.isAccessibilitySize }

    private var announcement: String {
        switch arrival.kind {
        case .signal: "\(countPrefix)Psst from \(name)"
        case .superPsst: "\(countPrefix)Super Psst from \(name)"
        case .joined: "\(name) is in. You're connected."
        case .sameMoment: "Same moment. You and \(name) pssted each other at the same time."
        }
    }

    private var hint: String {
        switch arrival.kind {
        case .signal, .superPsst: "Sends a Psst back."
        case .joined: "Sends your first Psst."
        case .sameMoment: "Closes."
        }
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView { if arrival.kind == .sameMoment { sameMoment } else { single } }
                        .background((color ?? .personBand(name)).ignoresSafeArea())
                } else if arrival.kind == .sameMoment { sameMoment } else { single }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onCanvas)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Close", onDone)
        // Closing without sending anything back, outside the tap-to-reply area.
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark", action: onDone)
                .labelStyle(.iconOnly)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.onCanvas)
                .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                .contentShape(Rectangle())
                .padding(Tokens.Space.s)
        }
        .accessibilityAddTraits(.isModal)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
        .sensoryFeedback(trigger: trigger) { _, _ in
            hapticsEnabled && arrival.kind == .sameMoment ? .success : nil
        }
        .task(id: arrival.id) {
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 150))
            trigger = arrival.id
            if hapticsEnabled, arrival.kind == .signal || arrival.kind == .superPsst {
                PsstHaptics.play(arrival.kind == .superPsst && superEffectsEnabled ? .superPsst : .psst)
            }
            guard !staysOpen else { return }
            try? await Task.sleep(for: holdTime)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }

    private var isPsst: Bool { arrival.kind == .signal || arrival.kind == .superPsst }
    /// Motion starts when `trigger` is set (just after the moment appears).
    private var settled: Bool { trigger != nil }

    /// FROM, their name, then "psst" in the wordmark's own lettering, with the
    /// reply as a band along the bottom, the same shape as everything you tap.
    private var single: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Tokens.Space.xxl)
            VStack(spacing: Tokens.Space.m) {
                if isPsst {
                    Text("FROM")
                        .font(.psst(.subheadline, weight: .bold))
                        .tracking(Tokens.Band.labelTracking * 2)
                }
                Text(name.uppercased())
                    .bandTitle(name, size: nameSize, tracking: Tokens.Band.titleTracking)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.5)
                    .offset(y: settled || reduceMotion ? 0 : 24)
                    .opacity(settled || !reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25), value: settled)
                Group {
                    if arrival.kind == .superPsst {
                        VStack(spacing: Tokens.Space.s) {
                            MischiefCat().frame(width: 84, height: 68)
                                .scaleEffect(!settled || reduceMotion ? 1 : 1.08)
                            Text("super psst")
                                .font(.psst(size: psstSize, weight: .heavy))
                                .tracking(Tokens.Band.wordmarkTracking)
                        }
                    } else if isPsst {
                        Text("psst")
                            .font(.psst(size: psstSize, weight: .heavy))
                            .tracking(Tokens.Band.wordmarkTracking)
                    } else {
                        Text("IS IN")
                            .bandTitle("is in", size: nameSize, tracking: Tokens.Band.titleTracking)
                    }
                }
                .opacity(settled ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25).delay(0.12), value: settled)
            }
            .padding(.horizontal, Tokens.Space.xl)
            Spacer(minLength: Tokens.Space.xxl)
            if !countPrefix.isEmpty {
                Text(countPrefix.trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
                    .font(.psst(.footnote, weight: .semibold))
                    .foregroundStyle(Color.onBandSoft)
                    .padding(.bottom, Tokens.Space.s)
            }
            Text(arrival.kind == .sameMoment ? "CLOSE" : isPsst ? "PSST BACK" : "PSST \(name.uppercased())")
                .font(.psst(size: replySize, weight: .black))
                .tracking(Tokens.Band.labelTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, Tokens.Space.xl)
                .frame(maxWidth: .infinity, minHeight: Tokens.Band.addBandMinHeight)
                .background(Color.bandShade.ignoresSafeArea(edges: .bottom))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((color ?? .personBand(name)).ignoresSafeArea())
    }

    /// Your half (the app's purple) above theirs, with SAME MOMENT across the seam.
    /// The two halves slide in from the top and bottom and meet at the seam
    /// (a crossfade with Reduce Motion); the sticker lands on top, slightly tilted.
    private var sameMoment: some View {
        VStack(spacing: 0) {
            half("You", color: .psstCanvas)
                .offset(y: settled || reduceMotion ? 0 : -80)
            half(name, color: color ?? .personBand(name))
                .offset(y: settled || reduceMotion ? 0 : 80)
        }
        .opacity(settled || !reduceMotion ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.35, bounce: 0.3), value: settled)
        .overlay {
            Text("SAME MOMENT")
                .font(.psst(size: labelSize, weight: .black))
                .tracking(Tokens.Band.titleTracking / 2)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
                .background(Color.surface)
                .rotationEffect(.degrees(-3))
                .scaleEffect(!settled ? (reduceMotion ? 1 : 0.6) : 1)
                .opacity(settled ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.35, bounce: 0.5).delay(0.2), value: settled)
                .padding(.horizontal, Tokens.Space.xl)
        }
    }

    private func half(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .bandTitle(title, size: nameSize, tracking: Tokens.Band.titleTracking)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.5)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.ignoresSafeArea())
    }
}
