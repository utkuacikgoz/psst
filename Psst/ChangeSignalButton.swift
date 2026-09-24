import SwiftUI

/// The separate, deliberate way to open signal choices for one person.
/// Stacks its two labels at accessibility text sizes so neither breaks mid-word.
struct ChangeSignalButton: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Space.xs))
                : AnyLayout(HStackLayout(spacing: Tokens.Space.s))
            layout {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Tokens.Space.s)
                }
                HStack(spacing: Tokens.Space.xs) {
                    Text("Change signal")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.onCanvas)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.black.opacity(0.15))
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
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
