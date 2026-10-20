import SwiftUI

/// What the gold + band opens (option I2): two big bands, each leading to one step.
struct InviteSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Opens straight on entering a code ("I have a code" on the empty home).
    var startEntering = false
    /// Opens straight on sharing a Psst link (the empty home's gold band, 2A).
    var startPsst = false

    private enum Mode { case choose, share, enter }

    @State private var mode: Mode = .choose

    // Share
    @State private var invite: CreatedInvite?
    /// Your open group code, once someone has joined with it (1C).
    @State private var progress: InviteProgress?
    @State private var isCreating = false
    @State private var createError: String?

    // Psst someone new (5A)
    @State private var psstShare: PsstShare?
    /// A link made but not yet shared: tapping again shares the same one (no new link, no invite used up).
    @State private var unsentPsst: PsstShare?
    @State private var unsentDoodle: PsstShare?
    @State private var askingNotifications = false
    @State private var creatingPsst = false
    @State private var psstError: String?
    /// After a Psst link is made: it waits for them until this date (3A).
    @State private var psstWaitingUntil: Date?
    /// Doodle as the invite (owner picks 1A 2A 3A 4A, 18 Oct 2026): the pad, and the
    /// drawing kept until its link is made, so a failed try doesn't lose it.
    @State private var drawingInvite = false
    @State private var inviteDoodle: DoodleStrokes?
    @State private var creatingDoodle = false
    @State private var doodleError: String?
    @State private var waitingIsDoodle = false

    // Enter
    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var isChecking = false
    @State private var isAccepting = false
    @State private var enterError: String?
    @FocusState private var codeFocused: Bool

    /// One size under home's band names, so each title fits one line on any iPhone (owner pick 1A, 20 Oct 2026).
    @ScaledMetric(relativeTo: .largeTitle) private var bandTitleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { content }
            } else if mode == .choose {
                // Four bands fill the sheet when they fit and scroll when they don't (small phones, larger text).
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }
                }
            } else { content }
        }
        .foregroundStyle(Color.onCanvas)
        .background(Color.psstCanvas.ignoresSafeArea())
        .presentationBackground(Color.psstCanvas)
        .sheet(item: $psstShare) { share in
            ShareSheet(items: share.items) { completed in shared(share, completed: completed) }
        }
        .sheet(isPresented: $askingNotifications) {
            NotificationAskCard { askingNotifications = false }
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $drawingInvite, onDismiss: { if inviteDoodle != nil { createDoodle() } }) {
            DoodleSheet(title: "For someone new", sendTitle: "SEND AS A LINK", color: Color(hex: 0xAC3E68)) { strokes in
                inviteDoodle = strokes
                return true
            }
        }
        .task { progress = try? await store.api.inviteProgress() }
        .onAppear {
            if startEntering {
                mode = .enter
                codeFocused = true
            }
            if startPsst { createPsst() }
            if let pending = store.pendingInviteCode {
                store.pendingInviteCode = nil
                code = pending
                mode = .enter
                check()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .choose: chooser
        case .share: shareStep
        case .enter: enterStep
        }
    }

    private var header: some View {
        HStack {
            Text("psst")
                .font(.psst(size: Tokens.Band.wordmarkSize, weight: .heavy))
                .tracking(Tokens.Band.wordmarkTracking)
            Spacer()
            Button(mode == .choose ? "Close" : "Back") {
                if mode == .choose { dismiss() } else { withAnimation { mode = .choose } }
            }
            .font(.psst(.body, weight: .semibold))
            .frame(minHeight: Tokens.minTouch)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.l)
    }

    // MARK: Choose

    private var chooser: some View {
        VStack(spacing: 0) {
            MischiefCat().frame(width: 48, height: 40)
                .frame(maxWidth: .infinity).padding(.top, Tokens.Space.s)
            // 5A (owner pick, 14 Oct): psst someone who isn't on Psst; the Psst is the invite.
            chooserBand(title: "Psst someone new",
                        subtitle: creatingPsst ? "Getting your Psst ready…" : "Not on Psst yet? Your Psst is the invite.",
                        color: Color(hex: 0xAC3E68), tag: "NEW") { createPsst() }
            if let psstError { errorLine(psstError) }
            chooserBand(title: "Draw someone new",
                        subtitle: creatingDoodle ? "Getting your doodle ready…"
                            : "Draw them something ✎ They see it when they join.",
                        color: Color(hex: 0xC2185B), tag: "NEW") {
                // A drawing whose link failed is sent again rather than drawn again; one
                // whose share was cancelled is offered again rather than lost.
                if let unsentDoodle {
                    psstShare = unsentDoodle.again()
                } else if inviteDoodle != nil { createDoodle() } else { drawingInvite = true }
            }
            if let doodleError { errorLine(doodleError) }
            // 3A (owner pick, 18 Oct 2026): say the Psst is waiting, and until when.
            if let psstWaitingUntil {
                Text("Your \(waitingIsDoodle ? "doodle" : "Psst") is waiting for them · expires \(psstWaitingUntil.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.psst(.subheadline, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, Tokens.Space.s)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.s)
            }
            chooserBand(title: "Share my invite", subtitle: progress?.summary() ?? "Send a link to your friends", color: .inviteGold) {
                withAnimation { mode = .share }
                // Keep sharing the code that's already filling up, rather than starting a new one.
                if invite == nil, let progress { invite = progress.invite }
                if invite == nil { create() }
            }
            chooserBand(title: "I have a code", subtitle: "Someone invited you", color: Color(hex: 0x5F61AE)) {
                withAnimation { mode = .enter }
                codeFocused = true
            }
        }
    }

    private func chooserBand(title: String, subtitle: String, color: Color, tag: String? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.s) {
                if let tag {
                    Text(tag)
                        .font(.psst(.caption, weight: .black))
                        .tracking(Tokens.Band.labelTracking)
                        .foregroundStyle(color)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, 2)
                        .background(Color.surface)
                }
                Text(title.uppercased())
                    .bandTitle(title, size: bandTitleSize, tracking: Tokens.Band.titleTracking)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.psst(.subheadline, weight: .medium))
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            .background(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }

    /// An error under its band, on its own line (1A), never in place of the band's subtitle.
    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.psst(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, Tokens.Space.s)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, Tokens.Space.l)
            .padding(.vertical, Tokens.Space.s)
            .onAppear { AccessibilityNotification.Announcement(message).post() }
    }

    // MARK: Share

    private var shareStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.m) {
                Text("YOUR CODE")
                    .font(.psst(.subheadline, weight: .bold))
                    .tracking(Tokens.Band.labelTracking * 2)
                if let invite {
                    Text(dynamicTypeSize.isAccessibilitySize ? "\(invite.code.prefix(4))\n\(invite.code.suffix(4))" : invite.displayCode)
                        .font(.system(size: codeSize, weight: .bold, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                    if let progress, progress.code == invite.code {
                        joinedDots(progress)
                        Text(progress.summary())
                            .font(.psst(.subheadline, weight: .bold))
                        if !progress.joined.isEmpty {
                            Text(progress.joined.joined(separator: ", "))
                                .font(.psst(.subheadline, weight: .medium))
                        }
                    } else {
                        Text("\(invite.usesLine) · expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.psst(.subheadline, weight: .medium))
                    }
                } else if let createError {
                    Label(createError, systemImage: "exclamationmark.circle")
                        .font(.psst(.subheadline, weight: .semibold))
                    Button("Try again", action: create)
                        .font(.psst(.body, weight: .semibold))
                        .frame(minHeight: Tokens.minTouch)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.inviteGold)

            if let invite {
                ShareLink(
                    item: invite.link,
                    message: Text("I want to be able to psst you. Tap to join me (code \(invite.code)).")
                ) {
                    Label(progress?.code == invite.code ? "Share again" : "Share invite", systemImage: "square.and.arrow.up")
                        .font(.psst(.body, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                        .background(Color.surface)
                }
            }
        }
    }

    /// One dot per place on the code, filled for each person who joined (1C).
    private func joinedDots(_ progress: InviteProgress) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<progress.maxUses, id: \.self) { index in
                Circle()
                    .fill(index < progress.uses ? Color.onCanvas : Color.onCanvas.opacity(0.3))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityHidden(true)
    }

    /// Makes a one-person link holding your Psst, then opens the share sheet (5A).
    private func createPsst() {
        guard !creatingPsst else { return }
        if let unsentPsst, (unsentPsst.expiresAt ?? .distantPast) > Date() {
            psstShare = unsentPsst.again()
            return
        }
        creatingPsst = true
        psstError = nil
        Task {
            do {
                let invite = try await store.api.createPsstInvite()
                let share = PsstShare(items: [PsstShare.message, invite.link], expiresAt: invite.expiresAt)
                unsentPsst = share
                psstShare = share
            } catch APIError.server(_, "too_many_invites") {
                psstError = "That's a lot of invites today. Try again tomorrow."
            } catch APIError.offline {
                psstError = "You're offline. Try again once you're back online."
            } catch {
                psstError = "Couldn't get your Psst ready. Try again."
            }
            creatingPsst = false
        }
    }

    /// "Waiting for them" only once the link really went somewhere (11A). The first
    /// time, Psst also asks about notifications if iOS hasn't had a yes or no (6A).
    private func shared(_ share: PsstShare, completed: Bool) {
        guard completed else { return }
        psstWaitingUntil = share.expiresAt
        waitingIsDoodle = share.isDoodle
        if share.isDoodle { unsentDoodle = nil } else { unsentPsst = nil }
        Task {
            guard await NotificationPermission.shouldAskAgain() else { return }
            // Let the share sheet finish closing first.
            try? await Task.sleep(for: .milliseconds(700))
            askingNotifications = true
        }
    }

    /// Makes a one-person link holding the drawing, then opens the share sheet.
    private func createDoodle() {
        guard let strokes = inviteDoodle, !creatingDoodle else { return }
        creatingDoodle = true
        doodleError = nil
        Task {
            do {
                let invite = try await store.api.createDoodleInvite(strokes: strokes)
                inviteDoodle = nil
                let share = PsstShare(items: [PsstShare.doodleMessage, invite.link], expiresAt: invite.expiresAt, isDoodle: true)
                unsentDoodle = share
                psstShare = share
            } catch APIError.server(_, "too_many_invites") {
                doodleError = "That's a lot of invites today. Try again tomorrow."
            } catch APIError.server(_, "invalid_doodle") {
                // The same strokes would fail again: draw a new one.
                inviteDoodle = nil
                doodleError = "Couldn't send that drawing. Draw another?"
            } catch APIError.offline {
                doodleError = "You're offline. Try again once you're back online."
            } catch {
                doodleError = "Couldn't get your doodle ready. Try again."
            }
            creatingDoodle = false
        }
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        createError = nil
        Task {
            do {
                invite = try await store.api.createInvite()
            } catch APIError.server(_, "too_many_invites") {
                createError = "You have 5 open invites. Wait for one to be used or expire."
            } catch APIError.offline {
                createError = "You're offline. Try again once you're back online."
            } catch {
                createError = "Couldn't make an invite. Try again."
            }
            isCreating = false
        }
    }

    // MARK: Enter

    /// The code from pasted text: an invite link (…/invite/K7QX4MPA), a shared
    /// message ("… (code K7QX 4MPA)") or the code itself, spaces and all.
    static func inviteCode(in text: String) -> String {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = source.range(of: "/invite/") {
            source = String(source[range.upperBound...].prefix { $0 != "?" && $0 != "#" && $0 != "/" })
        } else if let range = source.range(of: "code", options: [.caseInsensitive, .backwards]) {
            source = String(source[range.upperBound...])
        }
        return String(source.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16))
    }

    private var enterStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.m) {
                Text("THEIR CODE")
                    .font(.psst(.subheadline, weight: .bold))
                    .tracking(Tokens.Band.labelTracking * 2)
                TextField("", text: $code, prompt: Text("ABCDEFGH").foregroundStyle(Color.onCanvasSecondary))
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($codeFocused)
                    .onSubmit(check)
                    .disabled(isChecking || isAccepting)
                    .accessibilityLabel("Invite code")
                    .onChange(of: code) { preview = nil; enterError = nil }

                // Copied from the invite page or a message: no paste permission prompt.
                if code.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first.map(Self.inviteCode(in:)), !pasted.isEmpty else { return }
                        code = pasted
                        check()
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(.white)
                    .foregroundStyle(Color(hex: 0x5F61AE))
                }

                if let preview {
                    Text(Self.message(for: preview.status, name: preview.inviterName ?? "them"))
                        .font(.psst(.body, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let enterError {
                    Label(enterError, systemImage: "exclamationmark.circle")
                        .font(.psst(.subheadline, weight: .semibold))
                }
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x5F61AE))

            if let preview, preview.status == .pending {
                whiteBand(title: "Connect with \(preview.inviterName ?? "them")", busy: isAccepting, action: accept)
            } else if preview == nil {
                whiteBand(title: "Check code", busy: isChecking, action: check)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func whiteBand(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(Color.ink) }
            }
            .font(.psst(.body, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, Tokens.Space.xl)
            .padding(.vertical, Tokens.Space.s)
            .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
            .background(Color.surface)
            .contentShape(Rectangle())
        }
        .disabled(busy)
        .accessibilityLabel(title)
    }

    static func message(for status: InvitePreview.Status, name: String) -> String {
        switch status {
        case .pending: "\(name) invited you."
        case .own: "This is your own invite. Share it with someone else."
        case .used: "This invite has no places left. Ask for a new one."
        case .alreadyConnected: "You're already connected with \(name)."
        case .revoked: "This invite was cancelled. Ask for a new one."
        case .expired: "This invite has expired. Ask for a new one."
        case .invalid: "Hmm, that code doesn't match an invite. Check it and try again."
        }
    }

    private func check() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isChecking, !isAccepting else { return }
        isChecking = true
        enterError = nil
        Task {
            do {
                preview = try await store.api.previewInvite(code: trimmed)
            } catch APIError.offline {
                enterError = "You're offline. Try again once you're back online."
            } catch {
                enterError = "Couldn't check that code. Try again."
            }
            isChecking = false
        }
    }

    private func accept() {
        guard !isAccepting, !isChecking, preview?.status == .pending else { return }
        isAccepting = true
        enterError = nil
        Task {
            do {
                _ = try await store.acceptInvite(code: code)
                dismiss()
            } catch APIError.offline {
                enterError = "You're offline. Try again once you're back online."
            } catch {
                // The invite changed since it was checked; show its current state.
                preview = try? await store.api.previewInvite(code: code)
                if preview == nil { enterError = "Couldn't connect. Try again." }
            }
            isAccepting = false
        }
    }
}

/// What the share sheet sends for a Psst that is the invite.
struct PsstShare: Identifiable {
    let id = UUID()
    let items: [Any]
    var expiresAt: Date? = nil
    var isDoodle = false

    /// The same link, shared again (a new identity so the sheet opens again).
    func again() -> PsstShare { PsstShare(items: items, expiresAt: expiresAt, isDoodle: isDoodle) }

    static let message = "I pssted you. Open it to see, and psst me back."
    static let doodleMessage = "I drew you something. Open it to see, and psst me back."

    /// The same one-person link again (the day-5 reminder, 3A).
    static func resend(code: String) -> PsstShare? {
        guard let link = URL(string: "https://\(InviteLink.webHost)/p/\(code)") else { return nil }
        return PsstShare(items: [message, link])
    }
}

/// The system share sheet (Messages, WhatsApp, anything).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// True when the person actually sent or saved it, false when they cancelled.
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let onComplete = onComplete
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onComplete?(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 6A (owner pick, 20 Oct 2026): asked once, after the first Psst link you share,
/// if notifications are still quiet or never answered.
struct NotificationAskCard: View {
    let onDone: () -> Void
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: Tokens.Space.l) {
            MoodCat(mood: .awake)
                .frame(width: 44, height: 40)
                .padding(Tokens.Space.m)
                .background(Color.psstCanvas, in: Circle())
                .accessibilityHidden(true)
            Text("Hear it when they psst back?")
                .font(.psst(.title2, weight: .black))
                .foregroundStyle(Color.psstCanvas)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Turn on notifications and you'll know the moment they join and psst you.")
                .font(.psst(.subheadline, weight: .medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard !isAsking else { return }
                isAsking = true
                Task {
                    _ = await NotificationPermission.ask()
                    onDone()
                }
            } label: {
                Text("TURN ON")
                    .font(.psst(.body, weight: .black))
                    .tracking(Tokens.Band.labelTracking)
                    .foregroundStyle(Color.onCanvas)
                    .frame(maxWidth: .infinity, minHeight: Tokens.minTouch + Tokens.Space.s)
                    .background(Color.psstCanvas, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isAsking)
            Button("Not now", action: onDone)
                .font(.psst(.body, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .frame(minHeight: Tokens.minTouch)
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(Color.white)
    }
}
