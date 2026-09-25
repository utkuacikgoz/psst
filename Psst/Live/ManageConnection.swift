import SwiftUI

/// Remove, block or report one person.
struct ConnectionAction: Identifiable {
    enum Kind { case remove, block, report }

    let kind: Kind
    let connection: ConnectionSummary

    var id: String { "\(kind)-\(connection.id)" }
    private var name: String { connection.otherName }

    var menuTitle: String {
        switch kind {
        case .remove: "Remove \(name)"
        case .block: "Block \(name)"
        case .report: "Report \(name)"
        }
    }

    var question: String {
        switch kind {
        case .remove: "Remove \(name)?"
        case .block: "Block \(name)?"
        case .report: "Report \(name)?"
        }
    }

    var explanation: String {
        switch kind {
        case .remove: "You both stop seeing each other in Psst. You can connect again later with a new invite."
        case .block: "\(name) can't send you a Psst or connect with you again, and isn't told. You can unblock in Settings."
        case .report: "\(name) is blocked and the Psst team is sent a report to review. \(name) isn't told."
        }
    }

    var confirmTitle: String {
        switch kind {
        case .remove: "Remove"
        case .block: "Block"
        case .report: "Report and block"
        }
    }

    var systemImage: String {
        switch kind {
        case .remove: "person.badge.minus"
        case .block: "hand.raised"
        case .report: "exclamationmark.bubble"
        }
    }
}

/// Option P2: the standard iPhone action sheet (Remove, Block, Report, Cancel),
/// then an alert that explains what the choice does before anything happens.
private struct ManageConnectionModifier: ViewModifier {
    @Binding var menuFor: ConnectionSummary?
    @Binding var confirming: ConnectionAction?
    var onDone: () -> Void

    @Environment(LiveStore.self) private var store
    @State private var failedName: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                menuFor?.otherName ?? "",
                isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
                titleVisibility: .visible,
                presenting: menuFor
            ) { connection in
                ForEach([ConnectionAction.Kind.remove, .block, .report], id: \.self) { kind in
                    let action = ConnectionAction(kind: kind, connection: connection)
                    Button(action.menuTitle, role: kind == .remove ? nil : .destructive) { ask(action) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                confirming?.question ?? "",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                presenting: confirming
            ) { action in
                Button(action.confirmTitle, role: .destructive) { perform(action) }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(action.explanation)
            }
            .alert(
                "That didn't work",
                isPresented: Binding(get: { failedName != nil }, set: { if !$0 { failedName = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing changed with \(failedName ?? "them"). Check you're online and try again.")
            }
    }

    private func ask(_ action: ConnectionAction) {
        // Let the action sheet finish dismissing before the alert presents.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            confirming = action
        }
    }

    private func perform(_ action: ConnectionAction) {
        Task {
            do {
                switch action.kind {
                case .remove: try await store.remove(action.connection)
                case .block: try await store.block(action.connection)
                case .report: try await store.report(action.connection)
                }
                onDone()
            } catch {
                failedName = action.connection.otherName
            }
        }
    }
}

extension View {
    /// `menuFor` opens the action sheet; setting `confirming` directly (from a
    /// context menu item) skips straight to the explanation.
    func manageConnection(menuFor: Binding<ConnectionSummary?>,
                          confirming: Binding<ConnectionAction?>,
                          onDone: @escaping () -> Void = {}) -> some View {
        modifier(ManageConnectionModifier(menuFor: menuFor, confirming: confirming, onDone: onDone))
    }
}
