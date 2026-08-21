import AppKit
import SwiftUI

/// Flat, performance-look visual language, modelled on Gyors' theme schema. One
/// struct literal per theme; adding a theme means adding an entry to `all`.
///
/// Text runs three tiers — `foreground` (primary), `secondary` (real content
/// that isn't the headline), `dim` (hints, placeholders, the ms readout). Never
/// bake `.opacity()` into a text colour: over a translucent panel the alpha
/// multiplies with the substrate and the text goes mushy. Alpha on
/// `selectionBackground` is fine — that's a background, not text.
///
/// Kind badges are TheyDo-style chips: one shared hue per kind (`theydoKinds`,
/// still overridable per theme via `kindColors`), with a pastel gradient fill
/// and tinted text derived against each theme's background/foreground so chips
/// sit naturally in both light and dark themes.
struct Theme: Identifiable {
    let name: String
    let background: Color
    let foreground: Color
    let secondary: Color
    let dim: Color
    let accent: Color
    /// Alpha of the background tint over the blur substrate.
    var backgroundOpacity: Double = 0.92
    var usesBlur: Bool = true
    /// Multiplier on `accent` for the selected row's fill.
    var selectionOpacity: Double = 0.22
    var kindColors: [Destination.Kind: Color] = Theme.theydoKinds

    var id: String { name }

    /// Flat full-bleed accent wash across the whole row — no radius, no inset.
    var selectionBackground: Color { accent.opacity(selectionOpacity) }

    static let cornerRadius: CGFloat = 14
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
        .agenda: Color(hex: 0x9C36B5),    // grape (recurring-forum agendas)
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
        // Dark side keeps more chroma than it used to (was 0.74/0.84): blending
        // that far toward a near-black panel like Ember's #120C10 collapsed
        // every chip to the same mud. Only Mono Dark was that dark before, and
        // it overrides to monochrome, so the case never showed.
        let (top, bottom) = isDark ? (0.58, 0.70) : (0.87, 0.78)
        return (
            text: base.blended(toward: foreground, fraction: isDark ? 0.45 : 0.30),
            fillTop: base.blended(toward: background, fraction: top),
            fillBottom: base.blended(toward: background, fraction: bottom)
        )
    }

    // MARK: - Themes

    /// Gyors' published Ember theme, verbatim from the `gyors://theme?import=`
    /// sample on gyo.rs.
    static let ember = Theme(
        name: "Ember",
        background: Color(hex: 0x120C10),
        foreground: Color(hex: 0xFBF3EC),
        secondary: Color(hex: 0xA89B91),
        dim: Color(hex: 0x6B5E54),
        accent: Color(hex: 0xF97316),
        backgroundOpacity: 0.88
    )

    static let solarizedLight = Theme(
        name: "Solarized Light",
        background: Color(hex: 0xFDF6E3),
        foreground: Color(hex: 0x586E75),
        secondary: Color(hex: 0x657B83),
        dim: Color(hex: 0x93A1A1),
        accent: Color(hex: 0x268BD2),
        backgroundOpacity: 0.96,
        selectionOpacity: 0.18
    )

    static let solarizedDark = Theme(
        name: "Solarized Dark",
        background: Color(hex: 0x002B36),
        foreground: Color(hex: 0x93A1A1),
        secondary: Color(hex: 0x839496),
        dim: Color(hex: 0x586E75),
        accent: Color(hex: 0x268BD2)
    )

    static let gruvboxLight = Theme(
        name: "Gruvbox Light",
        background: Color(hex: 0xFBF1C7),
        foreground: Color(hex: 0x3C3836),
        secondary: Color(hex: 0x504945),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x458588),
        backgroundOpacity: 0.96,
        selectionOpacity: 0.18
    )

    static let gruvboxDark = Theme(
        name: "Gruvbox Dark",
        background: Color(hex: 0x282828),
        foreground: Color(hex: 0xEBDBB2),
        secondary: Color(hex: 0xD5C4A1),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x83A598)
    )

    static let catppuccinLatte = Theme(
        name: "Catppuccin Latte",
        background: Color(hex: 0xEFF1F5),
        foreground: Color(hex: 0x4C4F69),
        secondary: Color(hex: 0x6C6F85),
        dim: Color(hex: 0x9CA0B0),
        accent: Color(hex: 0x1E66F5),
        backgroundOpacity: 0.96,
        selectionOpacity: 0.18
    )

    static let catppuccinMocha = Theme(
        name: "Catppuccin Mocha",
        background: Color(hex: 0x1E1E2E),
        foreground: Color(hex: 0xCDD6F4),
        secondary: Color(hex: 0xA6ADC8),
        dim: Color(hex: 0x6C7086),
        accent: Color(hex: 0x89B4FA)
    )

    static let nord = Theme(
        name: "Nord",
        background: Color(hex: 0x2E3440),
        foreground: Color(hex: 0xD8DEE9),
        secondary: Color(hex: 0xA9B1C1),
        dim: Color(hex: 0x616E88),
        accent: Color(hex: 0x88C0D0)
    )

    static let dracula = Theme(
        name: "Dracula",
        background: Color(hex: 0x282A36),
        foreground: Color(hex: 0xF8F8F2),
        secondary: Color(hex: 0xBDC1D1),
        dim: Color(hex: 0x6272A4),
        accent: Color(hex: 0xBD93F9)
    )

    static let tokyoNight = Theme(
        name: "Tokyo Night",
        background: Color(hex: 0x1A1B26),
        foreground: Color(hex: 0xC0CAF5),
        secondary: Color(hex: 0x9AA5CE),
        dim: Color(hex: 0x565F89),
        accent: Color(hex: 0x7AA2F7)
    )

    static let monoDark = Theme(
        name: "Mono Dark",
        background: Color(hex: 0x0A0A0D),
        foreground: Color(hex: 0xEAEDE6),
        // Solid hexes, not foreground.opacity(): baked alpha on text goes mushy
        // over the blur substrate.
        secondary: Color(hex: 0xA6AAA5),
        dim: Color(hex: 0x6F706F),
        accent: Color(hex: 0xEAEDE6),
        selectionOpacity: 0.14,
        // Mono stays mono: chips derive from the foreground, not TheyDo hues.
        kindColors: [
            .project: Color(hex: 0xEAEDE6),
            .person: Color(hex: 0xEAEDE6),
            .personal: Color(hex: 0xEAEDE6),
            .reference: Color(hex: 0xEAEDE6),
            .general: Color(hex: 0xEAEDE6),
            .inbox: Color(hex: 0xEAEDE6),
            .list: Color(hex: 0xEAEDE6),
            .agenda: Color(hex: 0xEAEDE6),
        ]
    )

    static let all: [Theme] = [
        ember,
        solarizedLight, solarizedDark,
        gruvboxLight, gruvboxDark,
        catppuccinLatte, catppuccinMocha,
        nord, dracula, tokyoNight,
        monoDark,
    ]

    static let storageKey = "themeName"

    static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? .ember
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
