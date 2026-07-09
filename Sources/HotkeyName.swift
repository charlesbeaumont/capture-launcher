import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self(
        "toggleLauncher",
        default: .init(.space, modifiers: [.command, .control])
    )

    static let triageInbox = Self(
        "triageInbox",
        default: .init(.space, modifiers: [.command, .control, .shift])
    )
}
