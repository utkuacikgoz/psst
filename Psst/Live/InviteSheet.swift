import SwiftUI

/// Create and share an invite, or enter someone else's code.
struct InviteSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var invite: CreatedInvite?
    @State private var isCreating = false
    @State private var createError: String?

    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var isChecking = false
    @State private var isAccepting = false
    @State private var enterError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    shareSection
                    Divider()
                    enterSection
                }
                .padding(Tokens.sheetInset)
            }
            .psstSheetChrome(title: "Invite someone") { dismiss() }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .onAppear {
            if let pending = store.pendingInviteCode {
                store.pendingInviteCode = nil
                code = pending
                check()
            }
        }
    }

    // MARK: Share

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Send a link or code to one person. You can send each other signals once they accept.")
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let invite {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(invite.displayCode)
                        .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .textSelection(.enabled)
                        .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                    Text("Works once. Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }
                ShareLink(
                    item: invite.link,
                    message: Text("Connect with me on Psst. Open this link, or enter the code \(invite.code).")
                ) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .sheetButtonStyle(filled: true)
                }
            } else {
                Button(action: create) {
                    ZStack {
                        Text("Create invite").opacity(isCreating ? 0 : 1)
                        if isCreating { ProgressView().tint(.white) }
                    }
                    .sheetButtonStyle(filled: true)
                }
                .disabled(isCreating)
            }
            if let createError {
                Label(createError, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
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

    private var enterSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Have a code?")
                .font(.headline)
                .foregroundStyle(Color.ink)
            TextField("", text: $code, prompt: Text("ABCD EFGH").foregroundStyle(Color.inkSecondary))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(check)
                .padding(.horizontal, Tokens.Space.l)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Tokens.controlRadius).fill(Color.surfaceInset))
                .accessibilityLabel("Invite code")
                .onChange(of: code) { preview = nil; enterError = nil }

            if let preview {
                previewResult(preview)
            } else {
                Button(action: check) {
                    ZStack {
                        Text("Check code").opacity(isChecking ? 0 : 1)
                        if isChecking { ProgressView() }
                    }
                    .sheetButtonStyle(filled: false)
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
            }
            if let enterError {
                Label(enterError, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
            }
        }
    }

    @ViewBuilder
    private func previewResult(_ preview: InvitePreview) -> some View {
        let name = preview.inviterName ?? "them"
        switch preview.status {
        case .pending:
            Text("\(name) invited you.")
                .font(.body)
                .foregroundStyle(Color.ink)
            Button(action: accept) {
                ZStack {
                    Text("Connect with \(name)").opacity(isAccepting ? 0 : 1)
                    if isAccepting { ProgressView().tint(.white) }
                }
                .sheetButtonStyle(filled: true)
            }
            .disabled(isAccepting)
        default:
            Label(Self.message(for: preview.status, name: name), systemImage: "info.circle")
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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

extension View {
    /// Full-width 52 pt control for sheets: filled cobalt or outlined.
    func sheetButtonStyle(filled: Bool) -> some View {
        font(.body.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Color.psstCanvas)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Tokens.controlRadius)
                    .fill(filled ? Color.psstCanvas : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.controlRadius)
                    .stroke(Color.psstCanvas, lineWidth: filled ? 0 : 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Tokens.controlRadius))
    }
}
