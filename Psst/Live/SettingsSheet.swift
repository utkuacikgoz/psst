import SwiftUI
import UserNotifications

struct SettingsSheet: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var nameMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var blocked: [BlockedPerson] = []
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    section("Your name") {
                        HStack(spacing: Tokens.Space.s) {
                            TextField("", text: $name, prompt: Text("New name").foregroundStyle(Color.inkSecondary))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, Tokens.Space.m)
                                .frame(minHeight: Tokens.minTouch)
                                .background(RoundedRectangle(cornerRadius: Tokens.controlRadius).fill(Color.surfaceInset))
                                .accessibilityLabel("New name")
                            Button("Save", action: rename)
                                .font(.body.weight(.semibold))
                                .frame(minWidth: Tokens.minTouch, minHeight: Tokens.minTouch)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let nameMessage { caption(nameMessage) }
                    }

                    section("Notifications") {
                        caption(notificationText)
                        Button("Open notification settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Tokens.minTouch)
                    }

                    section("Blocked") {
                        if blocked.isEmpty {
                            caption("No one.")
                        }
                        ForEach(blocked) { person in
                            HStack {
                                Text(person.displayName).foregroundStyle(Color.ink)
                                Spacer()
                                Button("Unblock") { unblock(person) }
                                    .font(.body.weight(.semibold))
                                    .frame(minHeight: Tokens.minTouch)
                            }
                        }
                    }

                    section("Privacy") {
                        caption("Psst stores your name, your connections, and signals from the last 30 days, plus your device's notification token. It doesn't read your contacts or location, and there are no messages to store.")
                    }

                    section("Account") {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            if isDeleting { ProgressView() } else { Text("Delete account") }
                        }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Tokens.minTouch)
                        .disabled(isDeleting)
                        if let deleteError { caption(deleteError) }
                    }
                }
                .padding(Tokens.sheetInset)
            }
            .psstSheetChrome(title: "Settings") { dismiss() }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            blocked = (try? await store.api.listBlocked()) ?? []
        }
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await store.rename(to: trimmed)
                nameMessage = "Saved. People you're connected with now see \(trimmed)."
                name = ""
            } catch {
                nameMessage = "Couldn't save. Names can be 1 to 40 characters."
            }
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
                deleteError = "Couldn't delete your account. Check your connection and try again."
            }
            isDeleting = false
        }
    }
}
