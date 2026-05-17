import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self(
        "toggleLauncher",
        default: .init(.space, modifiers: [.command, .control])
    )
}
