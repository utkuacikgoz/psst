import SwiftUI

extension View {
    /// White sheet surface with an inline title and a Done button.
    func psstSheetChrome(title: String, doneTitle: String = "Done", onDone: @escaping () -> Void) -> some View {
        background(Color.surface)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(doneTitle, action: onDone) } }
    }
}

extension View {
    /// Pins `footer` below the scroll view at ordinary sizes; at accessibility
    /// sizes the caller places it inside the scroll content instead so it can't
    /// crowd out the person rows.
    @ViewBuilder
    func pinnedFooter<Footer: View>(_ isPinned: Bool, inset: CGFloat, @ViewBuilder footer: () -> Footer) -> some View {
        if isPinned {
            VStack(spacing: 0) {
                self
                footer()
                    .padding(.horizontal, inset)
                    .padding(.bottom, Tokens.Space.l)
            }
        } else {
            self
        }
    }
}
