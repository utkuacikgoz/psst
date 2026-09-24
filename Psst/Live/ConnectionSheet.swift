import SwiftUI

/// Signal choice for one connection, plus remove and block.
struct ConnectionSheet: View {
    let connection: ConnectionSummary

    @Environment(LiveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Signal
    @State private var confirming: Action?
    @State private var error: String?

    private enum Action: Identifiable {
        case remove, block
        var id: Self { self }
    }

    init(connection: ConnectionSummary) {
        self.connection = connection
        _selected = State(initialValue: connection.favorite)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    SignalChoiceContent(personName: connection.otherName, selected: selected) { signal in
                        let previous = selected
                        selected = signal
                        Task {
                            do {
                                try await store.setFavorite(signal, for: connection.id)
                            } catch {
                                selected = previous
                                self.error = "Couldn't save that choice. Try again."
                            }
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        Button("Remove \(connection.otherName)", role: .destructive) { confirming = .remove }
                            .frame(minHeight: Tokens.minTouch)
                        Button("Block \(connection.otherName)", role: .destructive) { confirming = .block }
                            .frame(minHeight: Tokens.minTouch)
                    }
                    .font(.body.weight(.semibold))
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
        } message: { action in
            switch action {
            case .remove:
                Text("You'll both stop seeing each other in Psst. You can connect again with a new invite.")
            case .block:
                Text("\(connection.otherName) won't be able to send you signals or connect with you again. They won't be told.")
            }
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
