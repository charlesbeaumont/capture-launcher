import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel
    let onHeightChange: (CGFloat) -> Void

    @AppStorage(Theme.storageKey) private var themeName = Theme.solarizedLight.name

    private enum Field { case compose, query }
    @FocusState private var focus: Field?

    private var theme: Theme { Theme.named(themeName) }

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
            TextField(
                "",
                text: $model.composeText,
                prompt: Text(model.composePlaceholder).foregroundColor(theme.dim),
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(theme.font(size: 20))
                .foregroundStyle(theme.foreground)
                .tint(theme.accent)
                .lineLimit(1...5)
                .focused($focus, equals: .compose)
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
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, model.mode == .triage ? 8 : 18)
        .overlay(alignment: .bottomLeading) {
            if model.mode == .triage {
                hintRow.padding(.leading, 28).padding(.bottom, -8)
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
                    .foregroundStyle(theme.dim)
                    .lineLimit(model.mode == .triage ? 4 : 2)
                Spacer(minLength: 8)
                if let counter = model.counterText {
                    Text(counter)
                        .font(theme.font(size: 12))
                        .foregroundStyle(theme.dim)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Text(">")
                    .font(theme.font(size: 16))
                    .foregroundStyle(theme.accent)
                TextField(
                    "",
                    text: $model.query,
                    prompt: Text(model.queryPlaceholder).foregroundColor(theme.dim)
                )
                    .textFieldStyle(.plain)
                    .font(theme.font(size: 16))
                    .foregroundStyle(theme.foreground)
                    .tint(theme.accent)
                    .focused($focus, equals: .query)
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
                    .font(theme.font(size: 10))
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)

            DestinationListView(
                ranked: model.ranked,
                selectionIndex: model.selectionIndex,
                theme: theme
            )

            hintRow
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 10)
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
            .font(theme.font(size: 10))
            .foregroundStyle(theme.dim)
    }

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 16))
            .foregroundStyle(theme.dim)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
