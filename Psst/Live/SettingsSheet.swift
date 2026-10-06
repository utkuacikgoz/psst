import SwiftUI
import UserNotifications

struct SettingsSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingName = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var blocked: [BlockedPerson] = []
    @State private var openInvites: [OpenInvite] = []
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var managing: ConnectionSummary?
    @State private var confirming: ConnectionAction?

    var body: some View {
        // Option S3: the standard grouped iPhone list.
        NavigationStack {
            Form {
                // ED1: you, as your people see you.
                Section {
                    YouBand(name: store.myName) { editingName = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.personBand(store.myName ?? "psst"))
                }

                Section {
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(notificationText)
                }

                Section {
                    if store.connections.isEmpty {
                        Text("No one yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.orderedConnections) { connection in
                        Button {
                            managing = connection
                        } label: {
                            HStack {
                                Text(connection.otherName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                        .accessibilityLabel("Manage \(connection.otherName)")
                    }
                    if !store.pinnedOrder.isEmpty {
                        Button("Sort everyone by most recent") { store.resetOrder() }
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Home puts whoever you pssted most recently first. Hold and drag a band to place someone yourself.")
                }

                // PI2: invites nobody has used yet, each cancellable.
                if !openInvites.isEmpty {
                    Section {
                        ForEach(openInvites) { invite in
                            HStack {
                                Text(invite.displayCode)
                                    .font(.body.monospaced())
                                    .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                                Spacer()
                                Text(invite.expiresAt, format: .relative(presentation: .named))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Expires \(invite.expiresAt.formatted(.relative(presentation: .named)))")
                                Button("Cancel") { revoke(invite) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Cancel invite \(invite.displayCode)")
                            }
                        }
                    } header: {
                        Text("Open invites")
                    } footer: {
                        Text("Each works once. Cancel one you sent to the wrong person.")
                    }
                }

                Section("Blocked") {
                    if blocked.isEmpty {
                        Text("No one.").foregroundStyle(.secondary)
                    }
                    ForEach(blocked) { person in
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            Button("Unblock") { unblock(person) }
                        }
                    }
                }

                Section {
                    Text("Psst stores your name, your connections, and signals from the last 30 days, plus your device's notification token. It doesn't read your contacts or location, and there are no messages to store.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Link("Privacy policy", destination: AppConfig.privacyURL)
                    Link("Terms of use", destination: AppConfig.termsURL)
                    Link("Help and support", destination: AppConfig.supportURL)
                } header: {
                    Text("Privacy and help")
                }

                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        if isDeleting { ProgressView() } else { Text("Delete account") }
                    }
                    .disabled(isDeleting)
                } footer: {
                    if let deleteError { Text(deleteError) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            blocked = (try? await store.api.listBlocked()) ?? []
            openInvites = (try? await store.api.listOpenInvites()) ?? []
        }
        .manageConnection(menuFor: $managing, confirming: $confirming) {
            Task { blocked = (try? await store.api.listBlocked()) ?? blocked }
        }
        .sheet(isPresented: $editingName) { NameEditSheet() }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your name, connections, and signal history from Psst's server. It can't be undone.")
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            "On. Sounds and alert style follow your iPhone's settings, including Focus and silent mode."
        case .denied:
            "Off. Signals still appear when you open Psst."
        default:
            "Not set up yet."
        }
    }

    private func revoke(_ invite: OpenInvite) {
        withAnimation { openInvites.removeAll { $0 == invite } }
        Task {
            try? await store.api.revokeInvite(code: invite.code)
            // Show the server's truth, whether or not the cancel went through.
            if let fresh = try? await store.api.listOpenInvites() { openInvites = fresh }
        }
    }

    private func unblock(_ person: BlockedPerson) {
        Task {
            try? await store.api.unblockUser(person.userId)
            blocked = (try? await store.api.listBlocked()) ?? blocked
        }
    }

    private func deleteAccount() {
        isDeleting = true
        deleteError = nil
        Task {
            do {
                try await store.deleteAccount()
                dismiss()
            } catch {
                deleteError = "Your account is still here: that didn't go through. Check you're online and try again."
            }
            isDeleting = false
        }
    }
}

/// ED1: the top of Settings. Your band in your colour, and one way to change it.
private struct YouBand: View {
    let name: String?
    let onEdit: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Tokens.Space.s) {
            Text("YOU")
                .font(.psst(.caption, weight: .bold))
                .tracking(Tokens.Band.labelTracking * 2)
                .accessibilityHidden(true)
            if let name {
                Text(name.uppercased())
                    .bandTitle(name, size: titleSize, tracking: Tokens.Band.titleTracking)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Your name: \(name)")
            } else {
                Text("Add the name your people see.")
                    .font(.psst(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            Button(action: onEdit) {
                Text(name == nil ? "Add your name" : "Edit name")
                    .font(.psst(.subheadline, weight: .bold))
                    .padding(.horizontal, Tokens.Space.l)
                    .padding(.vertical, Tokens.Space.s)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .padding(.top, Tokens.Space.xs)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Space.l)
        .padding(.horizontal, Tokens.Space.m)
    }
}
