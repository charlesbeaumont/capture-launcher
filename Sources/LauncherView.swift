import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel

    /// Resolved by the caller, not read from the environment. `LauncherPanel`
    /// pins its own appearance to the theme's darkness, so `colorScheme` in
    /// here reports the theme back at us rather than the system setting.
    let theme: Theme
    let onHeightChange: (CGFloat) -> Void

    private enum Field { case compose, query }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.stage {
            case .loading:
                statusRow("loading…")
            case .compose:
                composeStage
            case .route:
                routeStage
            case .done:
                statusRow("inbox clear")
            }
        }
        .frame(width: LauncherPanel.width, alignment: .leading)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geom in
                Color.clear
                    .preference(key: HeightKey.self, value: geom.size.height)
            }
        )
        .onPreferenceChange(HeightKey.self) { newHeight in
            onHeightChange(newHeight)
        }
        .onExitCommand { model.escape() }
        .onAppear { focus = .compose }
        .onChange(of: model.stage) {
            let target: Field? = model.stage == .route ? .query : .compose
            DispatchQueue.main.async { focus = target }
        }
    }

    // MARK: - Compose stage

    private var composeStage: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("", text: $model.composeText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(theme.font(size: 22).weight(.light))
                .foregroundStyle(theme.foreground)
                .tint(theme.accent)
                .lineLimit(1...5)
                .focused($focus, equals: .compose)
                .placeholder(model.composePlaceholder,
                             when: model.composeText.isEmpty,
                             theme: theme, size: 22)
                .onKeyPress(phases: .down) { press in
                    handleComposeKey(press)
                }
            if let counter = model.counterText {
                Text(counter)
                    .font(theme.font(size: 12))
                    .foregroundStyle(theme.dim)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, model.mode == .triage ? 8 : 18)
        .overlay(alignment: .bottomLeading) {
            if model.mode == .triage {
                hintRow.padding(.leading, 20).padding(.bottom, -8)
            }
        }
        .padding(.bottom, model.mode == .triage ? 14 : 0)
    }

    private func handleComposeKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return {
            if press.modifiers.contains(.shift) {
                model.composeText.append("\n")
                return .handled
            }
            model.submitCompose()
            return .handled
        }
        if model.mode == .triage {
            if press.key == .tab {
                model.skip()
                return .handled
            }
            if isDiscardChord(press) {
                model.discard()
                return .handled
            }
        }
        return .ignored
    }

    /// ⌘⌫ — matched on the raw characters too: the backspace key reports
    /// 0x7F or 0x08 depending on the path, and missing it here lets the
    /// system's "delete to start of line" binding eat the chord instead.
    private func isDiscardChord(_ press: KeyPress) -> Bool {
        guard press.modifiers.contains(.command) else { return false }
        if press.key == .delete { return true }
        return press.characters.contains("\u{7F}") || press.characters.contains("\u{08}")
    }

    // MARK: - Route stage

    private var routeStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(model.bannerText)
                    .font(theme.font(size: 13))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(model.mode == .triage ? 4 : 2)
                Spacer(minLength: 8)
                if let counter = model.counterText {
                    Text(counter)
                        .font(theme.font(size: 12))
                        .foregroundStyle(theme.dim)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField("", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(theme.font(size: 22).weight(.light))
                    .foregroundStyle(theme.foreground)
                    .tint(theme.accent)
                    .focused($focus, equals: .query)
                    .placeholder(model.queryPlaceholder,
                                 when: model.query.isEmpty,
                                 theme: theme, size: 22)
                    .onKeyPress(.upArrow) {
                        model.moveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(1)
                        return .handled
                    }
                    .onKeyPress(phases: .down) { press in
                        handleQueryKey(press)
                    }
                Text(String(format: "%.1fms", model.lastFilterMS))
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Full bleed, no inset — Gyors' query/list separator.
            Divider().opacity(0.3)

            DestinationListView(
                ranked: model.ranked,
                selectionIndex: model.selectionIndex,
                theme: theme
            )

            hintRow
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
    }

    private func handleQueryKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return {
            model.submitRoute()
            return .handled
        }
        if model.mode == .triage {
            if press.key == .tab {
                model.skip()
                return .handled
            }
            if isDiscardChord(press) {
                model.discard()
                return .handled
            }
        }
        return .ignored
    }

    // MARK: - Shared bits

    private var hintRow: some View {
        Text(model.hintText)
            .font(theme.font(size: 11))
            .foregroundStyle(theme.dim)
    }

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 16))
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
    }
}

private extension View {
    /// Own the placeholder instead of using `TextField(prompt:)`. SwiftUI
    /// overrides the prompt's `foregroundColor` with its own control styling,
    /// so a themed prompt renders at the system placeholder tone regardless of
    /// what we pass — too dark on Ember (Charles, 2026-08-21).
    func placeholder(_ text: String, when visible: Bool, theme: Theme, size: CGFloat) -> some View {
        overlay(alignment: .topLeading) {
            if visible {
                Text(text)
                    .font(theme.font(size: size).weight(.light))
                    .foregroundStyle(theme.secondary)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
