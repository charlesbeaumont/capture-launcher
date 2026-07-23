import AppKit
import SwiftUI

/// Flat, performance-look visual language. One struct literal per theme;
/// adding a theme means adding an entry to `all`. Kind badges are TheyDo-style
/// chips: one shared hue per kind (`theydoKinds`, still overridable per theme
/// via `kindColors`), with a pastel gradient fill and tinted text derived
/// against each theme's background/foreground so chips sit naturally in both
/// light and dark themes.
struct Theme: Identifiable {
    let name: String
    let background: Color
    let foreground: Color
    let dim: Color
    let accent: Color
    var kindColors: [Destination.Kind: Color] = Theme.theydoKinds

    var id: String { name }

    // Selection is an inset rounded highlight (Raycast-style); text keeps its colors.
    var selectionBackground: Color { foreground.opacity(0.10) }

    static let cornerRadius: CGFloat = 16
    static let rowHeight: CGFloat = 36
    static let listRows = 8

    /// Standard system font (SF Pro) — the pixel font was "a bit too much".
    func font(size: CGFloat) -> Font {
        .system(size: size)
    }

    func badgeColor(for kind: Destination.Kind) -> Color {
        kindColors[kind] ?? dim
    }

    // MARK: - TheyDo chips

    /// TheyDo-like hues (violet core, warm pink, teal, amber; 2026-07).
    static let theydoKinds: [Destination.Kind: Color] = [
        .project: Color(hex: 0x6B4EE6),   // violet (brand core)
        .person: Color(hex: 0xE64980),    // magenta-pink
        .personal: Color(hex: 0x0CA678),  // teal
        .reference: Color(hex: 0xE8930C), // amber
        .general: Color(hex: 0x0C8CE9),   // info blue
        .inbox: Color(hex: 0x6E6A63),     // warm ink-gray
        .list: Color(hex: 0xF76707),      // deep orange (running lists)
    ]

    var isDark: Bool {
        let ns = NSColor(background).usingColorSpace(.sRGB) ?? .white
        let luminance = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return luminance < 0.5
    }

    /// Chip colors for a kind: pastel gradient fill + tinted text, derived
    /// from the kind hue against this theme's background/foreground.
    func chip(for kind: Destination.Kind) -> (text: Color, fillTop: Color, fillBottom: Color) {
        let base = badgeColor(for: kind)
        let (top, bottom) = isDark ? (0.74, 0.84) : (0.87, 0.78)
        return (
            text: base.blended(toward: foreground, fraction: isDark ? 0.45 : 0.30),
            fillTop: base.blended(toward: background, fraction: top),
            fillBottom: base.blended(toward: background, fraction: bottom)
        )
    }

    // MARK: - Themes

    static let solarizedLight = Theme(
        name: "Solarized Light",
        background: Color(hex: 0xFDF6E3),
        foreground: Color(hex: 0x586E75),
        dim: Color(hex: 0x93A1A1),
        accent: Color(hex: 0x268BD2)
    )

    static let solarizedDark = Theme(
        name: "Solarized Dark",
        background: Color(hex: 0x002B36),
        foreground: Color(hex: 0x93A1A1),
        dim: Color(hex: 0x586E75),
        accent: Color(hex: 0x268BD2)
    )

    static let gruvboxLight = Theme(
        name: "Gruvbox Light",
        background: Color(hex: 0xFBF1C7),
        foreground: Color(hex: 0x3C3836),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x458588)
    )

    static let gruvboxDark = Theme(
        name: "Gruvbox Dark",
        background: Color(hex: 0x282828),
        foreground: Color(hex: 0xEBDBB2),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x83A598)
    )

    static let catppuccinLatte = Theme(
        name: "Catppuccin Latte",
        background: Color(hex: 0xEFF1F5),
        foreground: Color(hex: 0x4C4F69),
        dim: Color(hex: 0x9CA0B0),
        accent: Color(hex: 0x1E66F5)
    )

    static let catppuccinMocha = Theme(
        name: "Catppuccin Mocha",
        background: Color(hex: 0x1E1E2E),
        foreground: Color(hex: 0xCDD6F4),
        dim: Color(hex: 0x6C7086),
        accent: Color(hex: 0x89B4FA)
    )

    static let nord = Theme(
        name: "Nord",
        background: Color(hex: 0x2E3440),
        foreground: Color(hex: 0xD8DEE9),
        dim: Color(hex: 0x616E88),
        accent: Color(hex: 0x88C0D0)
    )

    static let dracula = Theme(
        name: "Dracula",
        background: Color(hex: 0x282A36),
        foreground: Color(hex: 0xF8F8F2),
        dim: Color(hex: 0x6272A4),
        accent: Color(hex: 0xBD93F9)
    )

    static let tokyoNight = Theme(
        name: "Tokyo Night",
        background: Color(hex: 0x1A1B26),
        foreground: Color(hex: 0xC0CAF5),
        dim: Color(hex: 0x565F89),
        accent: Color(hex: 0x7AA2F7)
    )

    static let monoDark = Theme(
        name: "Mono Dark",
        background: Color(hex: 0x0A0A0D),
        foreground: Color(hex: 0xEAEDE6),
        dim: Color(hex: 0xEAEDE6).opacity(0.45),
        accent: Color(hex: 0xEAEDE6),
        // Mono stays mono: chips derive from the foreground, not TheyDo hues.
        kindColors: [
            .project: Color(hex: 0xEAEDE6),
            .person: Color(hex: 0xEAEDE6),
            .personal: Color(hex: 0xEAEDE6),
            .reference: Color(hex: 0xEAEDE6),
            .general: Color(hex: 0xEAEDE6),
            .inbox: Color(hex: 0xEAEDE6),
            .list: Color(hex: 0xEAEDE6),
        ]
    )

    static let all: [Theme] = [
        solarizedLight, solarizedDark,
        gruvboxLight, gruvboxDark,
        catppuccinLatte, catppuccinMocha,
        nord, dracula, tokyoNight,
        monoDark,
    ]

    static let storageKey = "themeName"

    static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? .solarizedLight
    }

    static var current: Theme {
        named(UserDefaults.standard.string(forKey: storageKey) ?? "")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Blend toward another color in sRGB (0 = self, 1 = other).
    func blended(toward other: Color, fraction: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(a.blended(withFraction: fraction, of: b) ?? a)
    }
}
