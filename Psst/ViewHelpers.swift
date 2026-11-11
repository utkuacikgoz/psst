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

extension View {
    /// Centred in the space it's given when it fits; scrolls when it's taller, at the
    /// largest text sizes, instead of clipping (16A, owner pick 10 Nov 2026). Used by
    /// the first tip and the doodle tip.
    func scrollsWhenTall() -> some View {
        ViewThatFits(in: .vertical) {
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView { self.frame(maxWidth: .infinity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
