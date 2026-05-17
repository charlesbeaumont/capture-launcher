import SwiftUI

struct LauncherView: View {
    @State private var text: String = ""
    @FocusState private var focused: Bool

    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        TextField("Capture a thought…", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .regular, design: .default))
            .foregroundStyle(.primary)
            .tint(.primary)
            .lineLimit(1...5)
            .focused($focused)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(width: LauncherPanel.width, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            .onKeyPress(phases: .down) { press in
                guard press.key == .return else { return .ignored }
                if press.modifiers.contains(.shift) {
                    text.append("\n")
                    return .handled
                }
                submit()
                return .handled
            }
            .onExitCommand { onCancel() }
            .onAppear {
                text = ""
                focused = true
            }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onCancel()
            return
        }
        onSubmit(trimmed)
        text = ""
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
