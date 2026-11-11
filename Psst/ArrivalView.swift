import SwiftUI

/// A full-screen moment: a Psst that just arrived (R2), someone new (J2), or
/// both of you pssting within 10 seconds by the server's clock (X2).
struct Arrival: Identifiable, Equatable {
    enum Kind { case signal, joined, sameMoment, superPsst, doodle }

    /// The signal event (or, for a welcome, the connection), so it never shows twice.
    let id: UUID
    let connectionID: UUID?
    let senderName: String
    var kind: Kind = .signal
    /// A doodle's strokes (kind .doodle); shown as a polaroid.
    var doodle: DoodleStrokes? = nil
    /// MA2: when several people pssted, each gets a moment; "2 of 3".
    var position: Int? = nil
    var total: Int? = nil
    /// One quiet line under "psst", e.g. "Sent yesterday, before you had Psst" (5A).
    var note: String? = nil
    /// The sender's Psst+ word, shown where "psst" is (1A); nil = "psst".
    var word: String? = nil
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
    /// A doodle's ••• menu (owner pick 1B, 16 Oct 2026): take it off your widget
    /// without pssting back, or block or report the sender, where you see it.
    var onHideDoodle: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    /// 12A (owner pick, 10 Nov 2026): opens Psst+ at the word card. Pass it only when
    /// you don't have Psst+; nil never shows the "Pick yours" chip.
    var onPickWord: (() -> Void)? = nil

    @State private var showingOptions = false
    /// This moment shows the "Pick yours" chip (decided once when it appears).
    @State private var showsWordChip = false
    /// A finger is on the chip, so the moment doesn't close under it.
    @State private var chipPressed = false
    private var hasOptions: Bool { arrival.kind == .doodle && onBlock != nil && onReport != nil }

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
        // Rare ones linger: a same moment, or a doodle someone drew for you. So does
        // a moment with the "Pick yours" chip (12A), so it can be read and tapped.
        if arrival.kind == .sameMoment || arrival.kind == .doodle || showsWordChip { return Self.sameMomentTime }
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
    @Environment(\.scenePhase) private var scenePhase
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
        case .signal: arrival.word.map { "\(countPrefix)\($0) from \(name)" } ?? "\(countPrefix)Psst from \(name)"
        case .superPsst: "\(countPrefix)Super Psst from \(name)"
        case .doodle: "\(countPrefix)\(name) drew you a doodle"
        case .joined: "\(name) is in. You're connected."
        case .sameMoment: "Same moment. You and \(name) pssted each other at the same time."
        }
    }

    private var hint: String {
        switch arrival.kind {
        case .signal, .superPsst, .doodle: "Sends a Psst back."
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
        .accessibilityActions {
            if showsWordChip { Button("Pick your own word", action: pickWord) }
            if hasOptions {
                if let onHideDoodle { Button("Hide doodle", action: onHideDoodle) }
                if let onBlock { Button("Block \(name)", action: onBlock) }
                if let onReport { Button("Report \(name)", action: onReport) }
            }
        }
        .overlay(alignment: .topLeading) { if hasOptions { doodleOptions } }
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
            showsWordChip = decideWordChip()
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 150))
            trigger = arrival.id
            if hapticsEnabled, arrival.kind == .signal || arrival.kind == .superPsst || arrival.kind == .doodle {
                PsstHaptics.play(arrival.kind == .superPsst && superEffectsEnabled ? .superPsst : .psst)
            }
        }
        // Closes on its own, but never while the doodle's ••• menu is open or Psst
        // isn't on screen (so a moment nobody saw doesn't close itself); the wait
        // starts again after.
        .task(id: AutoClose(arrival: arrival.id, paused: showingOptions || chipPressed || scenePhase != .active,
                            chip: showsWordChip)) {
            guard !staysOpen, !showingOptions, !chipPressed, scenePhase == .active else { return }
            try? await Task.sleep(for: holdTime + .milliseconds(reduceMotion ? 0 : 150))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }

    private struct AutoClose: Hashable {
        let arrival: UUID
        let paused: Bool
        let chip: Bool
    }

    /// 12A: a Psst+ friend's own word, you without Psst+, and not shown in the last
    /// week. Showing it now starts the next week.
    private func decideWordChip() -> Bool {
        guard onPickWord != nil, arrival.kind == .signal, arrival.word != nil else { return false }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: WordChip.shownKey) as? Date
        guard WordChip.isDue(lastShown: last, now: .now) else { return false }
        defaults.set(Date.now, forKey: WordChip.shownKey)
        return true
    }

    private func pickWord() {
        chipPressed = false
        onPickWord?()
    }

    /// "Mia's word · Pick yours ›", quietly under their word (12A).
    private var wordChip: some View {
        Button(action: pickWord) {
            Text("\(name)'s word · Pick yours ›")
                .font(.psst(.caption, weight: .bold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .padding(.horizontal, Tokens.Space.m + 2)
                .padding(.vertical, Tokens.Space.s - 1)
                .background(Color.quietCapsule, in: Capsule())
                .frame(minHeight: Tokens.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle(pressed: $chipPressed))
        .padding(.top, Tokens.Space.xs)
    }

    /// ••• top left (1B): Hide doodle, Block, Report, in a small dark menu. A tap
    /// anywhere else closes the menu instead of pssting back.
    private var doodleOptions: some View {
        ZStack(alignment: .topLeading) {
            if showingOptions {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showingOptions = false }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Button {
                    showingOptions.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.black))
                        .foregroundStyle(Color.onCanvas)
                        .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
                if showingOptions {
                    VStack(alignment: .leading, spacing: 0) {
                        if let onHideDoodle {
                            optionRow("Hide doodle", destructive: false, action: onHideDoodle)
                            optionDivider
                        }
                        if let onBlock { optionRow("Block \(name)", destructive: true, action: onBlock) }
                        optionDivider
                        if let onReport { optionRow("Report \(name)", destructive: true, action: onReport) }
                    }
                    // As wide as its longest row, 220 to 320 (6A, 18 Oct 2026); longer names wrap.
                    .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(Color(white: 0.16).opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity)
                }
            }
            .padding(Tokens.Space.s)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showingOptions)
    }

    private var optionDivider: some View {
        Rectangle().fill(Color(white: 0.28)).frame(height: 0.5)
    }

    private func optionRow(_ title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            showingOptions = false
            action()
        } label: {
            Text(title)
                .font(.psst(.body, weight: .medium))
                .foregroundStyle(destructive ? Color(red: 1, green: 0.41, blue: 0.38) : .white)
                .lineLimit(2)
                .padding(.vertical, Tokens.Space.xs)
                .frame(maxWidth: .infinity, minHeight: Tokens.minTouch, alignment: .leading)
                .padding(.horizontal, Tokens.Space.m)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isPsst: Bool { arrival.kind == .signal || arrival.kind == .superPsst || arrival.kind == .doodle }
    /// Motion starts when `trigger` is set (just after the moment appears).
    private var settled: Bool { trigger != nil }

    /// FROM, their name, then "psst" in the wordmark's own lettering, with the
    /// reply as a band along the bottom, the same shape as everything you tap.
    private var single: some View {
        singleContent
            // A Super Psst arrives as a nudge: the screen shakes like the old MSN nudge
            // (owner pick 1A, 14 Oct). With Reduce Motion, the cat's soft pulse only.
            .keyframeAnimator(initialValue: 0.0, trigger: arrival.kind == .superPsst ? trigger : nil) { content, x in
                content.offset(x: reduceMotion ? 0 : CGFloat(x))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-16, duration: 0.05)
                    LinearKeyframe(16, duration: 0.08)
                    LinearKeyframe(-14, duration: 0.08)
                    LinearKeyframe(14, duration: 0.08)
                    LinearKeyframe(-10, duration: 0.08)
                    LinearKeyframe(10, duration: 0.08)
                    LinearKeyframe(-4, duration: 0.07)
                    LinearKeyframe(0, duration: 0.07)
                }
            }
    }

    private var singleContent: some View {
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
                .multilineTextAlignment(.center)
                    .offset(y: settled || reduceMotion ? 0 : 24)
                    .opacity(settled || !reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25), value: settled)
                Group {
                    if arrival.kind == .doodle {
                        // 3B: the doodle as a little polaroid.
                        if let doodle = arrival.doodle {
                            DoodlePolaroid(strokes: doodle, name: name, color: (color ?? .personBand(name)).opacity(0.85),
                                           width: 220)
                        } else {
                            Text("drew you something ✎")
                                .font(.psst(.title2, weight: .heavy))
                        }
                    } else if arrival.kind == .superPsst {
                        VStack(spacing: Tokens.Space.s) {
                            MischiefCat().frame(width: 84, height: 68)
                                .scaleEffect(!settled || reduceMotion ? 1 : 1.08)
                            Text("super psst")
                                .font(.psst(size: psstSize, weight: .heavy))
                                .tracking(Tokens.Band.wordmarkTracking)
                        }
                    } else if isPsst {
                        VStack(spacing: Tokens.Space.s) {
                            Group {
                                if arrival.kind == .signal, let word = arrival.word { Text(verbatim: word) } else { Text("psst") }
                            }
                            .font(.psst(size: psstSize, weight: .heavy))
                            .tracking(Tokens.Band.wordmarkTracking)
                            if let note = arrival.note {
                                Text(note).font(.psst(.subheadline, weight: .semibold))
                            }
                            if showsWordChip { wordChip }
                        }
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Space.xl)
                .frame(maxWidth: .infinity, minHeight: Tokens.Band.addBandMinHeight)
                .background(Color.bandShade.ignoresSafeArea(edges: .bottom))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 4B (owner pick, 14 Oct 2026): a startled cat peeks in from the edge.
        .overlay(alignment: .topTrailing) {
            if arrival.kind == .signal {
                StartledPeekCat(eyes: color ?? .personBand(name), shown: settled)
                    .padding(.top, 150)
            }
        }
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.5)
                .multilineTextAlignment(.center)
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

/// 12A (owner pick, 10 Nov 2026): when a Psst+ friend's own word arrives and you don't
/// have Psst+, a quiet chip offers yours, at most once a week.
enum WordChip {
    /// When the chip last showed on this phone.
    static let shownKey = "psst.wordChipShownAt"
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    static func isDue(lastShown: Date?, now: Date) -> Bool {
        guard let lastShown else { return true }
        // A clock set back counts as due rather than hiding the chip for good.
        return now.timeIntervalSince(lastShown) >= interval || now < lastShown
    }
}

/// Dims while pressed and reports the press, so the moment waits (12A).
private struct ChipPressStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onChange(of: configuration.isPressed) { _, new in pressed = new }
    }
}
