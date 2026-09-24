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

    static let controlRadius: CGFloat = 0
    static let minTouch: CGFloat = 44
    static let personRowMinHeight: CGFloat = 144
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

    /// Yo-inspired purple canvas.
    static let psstCanvas = Color(hex: 0x713F93)
    /// Main text on canvas.
    static let onCanvas = Color.white
    /// Secondary text on the purple canvas.
    static let onCanvasSecondary = Color.white.opacity(0.82)

    /// Raised person surface and sheets.
    static let surface = Color.white
    /// Pressed person surface. Ink on it stays above 13:1.
    static let surfacePressed = Color(hex: 0xEEE7F3)
    /// Inset areas inside sheets (preview stage, option rows).
    static let surfaceInset = Color(hex: 0xF5F0F7)
    /// Text and icons on white surfaces.
    static let ink = Color(hex: 0x292031)
    /// Secondary text on white surfaces.
    static let inkSecondary = Color(hex: 0x66586E)
}

extension Color {
    /// Stable name-derived colours: reordering contacts does not change their identity.
    static func personBand(_ name: String) -> Color {
        let palette: [UInt32] = [0x2476AA, 0x187F69, 0xB34F2B, 0xAC3E68, 0x5F61AE]
        let seed = name.lowercased().unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return Color(hex: palette[seed])
    }
    static let addBand = Color(hex: 0xB87500)
}

extension Text {
    /// Oversized band titles wrap between words but never inside one: each word
    /// gets at most one line, and a word too wide for the band scales down instead.
    func bandTitle(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        return font(.system(size: size, weight: .bold))
            .tracking(tracking)
            .lineLimit(words)
            .minimumScaleFactor(0.4)
    }
}
