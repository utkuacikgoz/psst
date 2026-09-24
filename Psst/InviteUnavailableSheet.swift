import SwiftUI

/// The add-person action exists, but invitations need accounts and a server. Say so plainly.
struct InviteUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Text("Invitations aren't available in this preview yet. When they are, you'll share a link or code, and you can send signals once both of you accept.")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(Tokens.sheetInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .navigationTitle("Invite someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Color.psstCanvas)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium])
    }
}
