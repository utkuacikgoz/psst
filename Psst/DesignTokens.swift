import SwiftUI

/// The single source of layout and colour values for the app. See DESIGN.md §2–3.
enum Tokens {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    static let controlRadius: CGFloat = 12
    static let minTouch: CGFloat = 44
    static let personRowMinHeight: CGFloat = 88
    static let sheetInset: CGFloat = 24

    /// 24 pt side inset, 20 pt on very narrow phones. Safe areas are excluded by the caller.
    static func sideInset(forWidth width: CGFloat) -> CGFloat {
        width < 360 ? 20 : 24
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Canvas. White text on it measures about 7.0:1.
    static let psstCanvas = Color(hex: 0x2448D8)
    /// Main text on canvas.
    static let onCanvas = Color.white
    /// Secondary text on canvas. White at 82% over cobalt measures about 5.2:1.
    static let onCanvasSecondary = Color.white.opacity(0.82)

    /// Raised person surface and sheets.
    static let surface = Color.white
    /// Pressed person surface. Ink on it stays above 13:1.
    static let surfacePressed = Color(hex: 0xE3E8FA)
    /// Inset areas inside sheets (preview stage, option rows).
    static let surfaceInset = Color(hex: 0xEEF1FB)
    /// Text and icons on the white surface: about 15:1.
    static let ink = Color(hex: 0x17224D)
    /// Secondary text on white surfaces: about 7:1.
    static let inkSecondary = Color(hex: 0x4A5580)
}
