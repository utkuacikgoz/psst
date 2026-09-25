import SwiftUI

/// Remove or block one person. Opened from Settings → People, a long press on
/// their band, or the VoiceOver "Manage" action.
struct ConnectionSheet: View {
    let connection: ConnectionSummary

    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Action?
    @State private var error: String?

    private enum Action: Identifiable {
        case remove, block
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    Text("Removing ends the connection for both of you. You can connect again later with a new invite.")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Remove \(connection.otherName)", role: .destructive) { confirming = .remove }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Tokens.minTouch)

                    Divider()

                    Text("Blocking also stops \(connection.otherName) from connecting with you again. They aren't told.")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Block \(connection.otherName)", role: .destructive) { confirming = .block }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Tokens.minTouch)

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                    }
                }
                .padding(Tokens.sheetInset)
            }
            .psstSheetChrome(title: connection.otherName) { dismiss() }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .confirmationDialog(
            confirming == .block ? "Block \(connection.otherName)?" : "Remove \(connection.otherName)?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            Button(action == .block ? "Block" : "Remove", role: .destructive) { perform(action) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func perform(_ action: Action) {
        Task {
            do {
                switch action {
                case .remove: try await store.remove(connection)
                case .block: try await store.block(connection)
                }
                dismiss()
            } catch {
                self.error = "Couldn't update this connection. Check your connection and try again."
            }
        }
    }
}
