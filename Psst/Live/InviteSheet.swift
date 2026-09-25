import SwiftUI

/// What the gold + band opens (option I2): two big bands, each leading to one step.
struct InviteSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case choose, share, enter }

    @State private var mode: Mode = .choose

    // Share
    @State private var invite: CreatedInvite?
    @State private var isCreating = false
    @State private var createError: String?

    // Enter
    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var isChecking = false
    @State private var isAccepting = false
    @State private var enterError: String?
    @FocusState private var codeFocused: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var bandTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            switch mode {
            case .choose: chooser
            case .share: shareStep
            case .enter: enterStep
            }
        }
        .foregroundStyle(Color.onCanvas)
        .background(Color.psstCanvas.ignoresSafeArea())
        .presentationBackground(Color.psstCanvas)
        .onAppear {
            if let pending = store.pendingInviteCode {
                store.pendingInviteCode = nil
                code = pending
                mode = .enter
                check()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("psst")
                .font(.system(size: Tokens.Band.wordmarkSize, weight: .heavy))
                .tracking(Tokens.Band.wordmarkTracking)
            Spacer()
            Button(mode == .choose ? "Cancel" : "Back") {
                if mode == .choose { dismiss() } else { withAnimation { mode = .choose } }
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: Tokens.minTouch)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.l)
    }

    // MARK: Choose

    private var chooser: some View {
        VStack(spacing: 0) {
            chooserBand(title: "Share my invite", subtitle: "Send a link to one person", color: .addBand) {
                withAnimation { mode = .share }
                if invite == nil { create() }
            }
            chooserBand(title: "I have a code", subtitle: "Someone sent you one", color: Color(hex: 0x5F61AE)) {
                withAnimation { mode = .enter }
                codeFocused = true
            }
        }
    }

    private func chooserBand(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.s) {
                Text(title.uppercased())
                    .bandTitle(title, size: bandTitleSize, tracking: Tokens.Band.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Share

    private var shareStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.m) {
                Text("YOUR CODE")
                    .font(.subheadline.weight(.bold))
                    .tracking(Tokens.Band.labelTracking * 2)
                if let invite {
                    Text(invite.displayCode)
                        .font(.system(size: codeSize, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                    Text("Works once · expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.medium))
                } else if let createError {
                    Label(createError, systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Button("Try again", action: create)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Tokens.minTouch)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.addBand)

            if let invite {
                ShareLink(
                    item: invite.link,
                    message: Text("Connect with me on Psst. Open this link, or enter the code \(invite.code).")
                ) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Band.barMinHeight)
                        .background(Color.surface)
                }
            }
        }
    }

    private func create() {
        isCreating = true
        createError = nil
        Task {
            do {
                invite = try await store.api.createInvite()
            } catch APIError.server(_, "too_many_invites") {
                createError = "You have 5 open invites. Wait for one to be used or expire."
            } catch APIError.offline {
                createError = "You're offline. Connect and try again."
            } catch {
                createError = "Couldn't create an invite. Try again."
            }
            isCreating = false
        }
    }

    // MARK: Enter

    private var enterStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Space.m) {
                Text("THEIR CODE")
                    .font(.subheadline.weight(.bold))
                    .tracking(Tokens.Band.labelTracking * 2)
                TextField("", text: $code, prompt: Text("ABCD EFGH").foregroundStyle(Color.onCanvasSecondary))
                    .font(.system(size: codeSize, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($codeFocused)
                    .onSubmit(check)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Invite code")
                    .onChange(of: code) { preview = nil; enterError = nil }

                if let preview {
                    Text(Self.message(for: preview.status, name: preview.inviterName ?? "them"))
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else if let enterError {
                    Label(enterError, systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
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
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
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
        case .used: "This invite has already been used. Ask for a new one."
        case .alreadyConnected: "You're already connected with \(name)."
        case .revoked: "This invite was cancelled. Ask for a new one."
        case .expired: "This invite has expired. Ask for a new one."
        case .invalid: "That code doesn't match an invite. Check it and try again."
        }
    }

    private func check() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isChecking = true
        enterError = nil
        Task {
            do {
                preview = try await store.api.previewInvite(code: trimmed)
            } catch APIError.offline {
                enterError = "You're offline. Connect and try again."
            } catch {
                enterError = "Couldn't check that code. Try again."
            }
            isChecking = false
        }
    }

    private func accept() {
        isAccepting = true
        enterError = nil
        Task {
            do {
                _ = try await store.acceptInvite(code: code)
                dismiss()
            } catch APIError.offline {
                enterError = "You're offline. Connect and try again."
            } catch {
                // The invite changed since it was checked; show its current state.
                preview = try? await store.api.previewInvite(code: code)
                if preview == nil { enterError = "Couldn't connect. Try again." }
            }
            isAccepting = false
        }
    }
}
