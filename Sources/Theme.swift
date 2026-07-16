import AppKit
import SwiftUI

/// Flat, performance-look visual language. One struct literal per theme;
/// adding a theme means adding an entry to `all`. Kind badges (the colored
/// project/person/personal/reference labels) take their colors from the
/// theme's own accent palette via `kindColors`.
struct Theme: Identifiable {
    let name: String
    let background: Color
    let foreground: Color
    let dim: Color
    let accent: Color
    /// Text color used inside kind badges (badge fills come from `kindColors`).
    let badgeText: Color
    let kindColors: [Destination.Kind: Color]

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

    // MARK: - Solarized

    private static let solarizedKinds: [Destination.Kind: Color] = [
        .project: Color(hex: 0x268BD2),   // blue
        .person: Color(hex: 0xD33682),    // magenta
        .personal: Color(hex: 0x859900),  // green
        .reference: Color(hex: 0xB58900), // yellow
        .general: Color(hex: 0x2AA198),   // cyan
        .inbox: Color(hex: 0x93A1A1),     // base1
    ]

    static let solarizedLight = Theme(
        name: "Solarized Light",
        background: Color(hex: 0xFDF6E3),
        foreground: Color(hex: 0x586E75),
        dim: Color(hex: 0x93A1A1),
        accent: Color(hex: 0x268BD2),
        badgeText: Color(hex: 0xFDF6E3),
        kindColors: solarizedKinds
    )

    static let solarizedDark = Theme(
        name: "Solarized Dark",
        background: Color(hex: 0x002B36),
        foreground: Color(hex: 0x93A1A1),
        dim: Color(hex: 0x586E75),
        accent: Color(hex: 0x268BD2),
        badgeText: Color(hex: 0xFDF6E3),
        kindColors: solarizedKinds
    )

    // MARK: - Gruvbox

    static let gruvboxLight = Theme(
        name: "Gruvbox Light",
        background: Color(hex: 0xFBF1C7),
        foreground: Color(hex: 0x3C3836),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x458588),
        badgeText: Color(hex: 0xFBF1C7),
        kindColors: [
            .project: Color(hex: 0x458588),   // blue
            .person: Color(hex: 0xB16286),    // purple
            .personal: Color(hex: 0x98971A),  // green
            .reference: Color(hex: 0xD79921), // yellow
            .general: Color(hex: 0x689D6A),   // aqua
            .inbox: Color(hex: 0x928374),     // gray
        ]
    )

    static let gruvboxDark = Theme(
        name: "Gruvbox Dark",
        background: Color(hex: 0x282828),
        foreground: Color(hex: 0xEBDBB2),
        dim: Color(hex: 0x928374),
        accent: Color(hex: 0x83A598),
        badgeText: Color(hex: 0x282828),
        kindColors: [
            .project: Color(hex: 0x83A598),   // blue
            .person: Color(hex: 0xD3869B),    // purple
            .personal: Color(hex: 0xB8BB26),  // green
            .reference: Color(hex: 0xFABD2F), // yellow
            .general: Color(hex: 0x8EC07C),   // aqua
            .inbox: Color(hex: 0x928374),     // gray
        ]
    )

    // MARK: - Catppuccin

    static let catppuccinLatte = Theme(
        name: "Catppuccin Latte",
        background: Color(hex: 0xEFF1F5),
        foreground: Color(hex: 0x4C4F69),
        dim: Color(hex: 0x9CA0B0),
        accent: Color(hex: 0x1E66F5),
        badgeText: Color(hex: 0xEFF1F5),
        kindColors: [
            .project: Color(hex: 0x1E66F5),   // blue
            .person: Color(hex: 0xEA76CB),    // pink
            .personal: Color(hex: 0x40A02B),  // green
            .reference: Color(hex: 0xDF8E1D), // yellow
            .general: Color(hex: 0x179299),   // teal
            .inbox: Color(hex: 0x9CA0B0),     // overlay
        ]
    )

    static let catppuccinMocha = Theme(
        name: "Catppuccin Mocha",
        background: Color(hex: 0x1E1E2E),
        foreground: Color(hex: 0xCDD6F4),
        dim: Color(hex: 0x6C7086),
        accent: Color(hex: 0x89B4FA),
        badgeText: Color(hex: 0x1E1E2E),
        kindColors: [
            .project: Color(hex: 0x89B4FA),   // blue
            .person: Color(hex: 0xF5C2E7),    // pink
            .personal: Color(hex: 0xA6E3A1),  // green
            .reference: Color(hex: 0xF9E2AF), // yellow
            .general: Color(hex: 0x94E2D5),   // teal
            .inbox: Color(hex: 0x9399B2),     // overlay2
        ]
    )

    // MARK: - Nord

    static let nord = Theme(
        name: "Nord",
        background: Color(hex: 0x2E3440),
        foreground: Color(hex: 0xD8DEE9),
        dim: Color(hex: 0x616E88),
        accent: Color(hex: 0x88C0D0),
        badgeText: Color(hex: 0x2E3440),
        kindColors: [
            .project: Color(hex: 0x81A1C1),   // frost blue
            .person: Color(hex: 0xB48EAD),    // aurora purple
            .personal: Color(hex: 0xA3BE8C),  // aurora green
            .reference: Color(hex: 0xEBCB8B), // aurora yellow
            .general: Color(hex: 0x88C0D0),   // frost cyan
            .inbox: Color(hex: 0x81A1C1).opacity(0.55),
        ]
    )

    // MARK: - Dracula

    static let dracula = Theme(
        name: "Dracula",
        background: Color(hex: 0x282A36),
        foreground: Color(hex: 0xF8F8F2),
        dim: Color(hex: 0x6272A4),
        accent: Color(hex: 0xBD93F9),
        badgeText: Color(hex: 0x282A36),
        kindColors: [
            .project: Color(hex: 0xBD93F9),   // purple
            .person: Color(hex: 0xFF79C6),    // pink
            .personal: Color(hex: 0x50FA7B),  // green
            .reference: Color(hex: 0xF1FA8C), // yellow
            .general: Color(hex: 0x8BE9FD),   // cyan
            .inbox: Color(hex: 0x6272A4),     // comment
        ]
    )

    // MARK: - Tokyo Night

    static let tokyoNight = Theme(
        name: "Tokyo Night",
        background: Color(hex: 0x1A1B26),
        foreground: Color(hex: 0xC0CAF5),
        dim: Color(hex: 0x565F89),
        accent: Color(hex: 0x7AA2F7),
        badgeText: Color(hex: 0x1A1B26),
        kindColors: [
            .project: Color(hex: 0x7AA2F7),   // blue
            .person: Color(hex: 0xBB9AF7),    // magenta
            .personal: Color(hex: 0x9ECE6A),  // green
            .reference: Color(hex: 0xE0AF68), // yellow
            .general: Color(hex: 0x7DCFFF),   // cyan
            .inbox: Color(hex: 0x737AA2),     // comment (lightened)
        ]
    )

    // MARK: - Mono

    static let monoDark = Theme(
        name: "Mono Dark",
        background: Color(hex: 0x0A0A0D),
        foreground: Color(hex: 0xEAEDE6),
        dim: Color(hex: 0xEAEDE6).opacity(0.45),
        accent: Color(hex: 0xEAEDE6),
        badgeText: Color(hex: 0xEAEDE6),
        kindColors: [
            .project: Color(hex: 0xEAEDE6).opacity(0.22),
            .person: Color(hex: 0xEAEDE6).opacity(0.22),
            .personal: Color(hex: 0xEAEDE6).opacity(0.22),
            .reference: Color(hex: 0xEAEDE6).opacity(0.22),
            .general: Color(hex: 0xEAEDE6).opacity(0.22),
            .inbox: Color(hex: 0xEAEDE6).opacity(0.22),
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
}
