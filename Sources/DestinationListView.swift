import SwiftUI

/// Fixed-viewport destination list: always `Theme.listRows` rows tall so the
/// panel never resizes while filtering; unfilled rows stay blank. Selection
/// is an inset rounded highlight.
struct DestinationListView: View {
    let ranked: [RankedDestination]
    let selectionIndex: Int
    let theme: Theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rows
            }
            .frame(height: CGFloat(Theme.listRows) * Theme.rowHeight)
            .onChange(of: selectionIndex) { _, newIndex in
                proxy.scrollTo(newIndex)
            }
            .onChange(of: ranked.count) {
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                row(item.destination, selected: index == selectionIndex)
                    .id(index)
            }
        }
    }

    private func row(_ destination: Destination, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(destination.leafName)
                .font(theme.font(size: 15))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
            if !destination.registered {
                Text("·new")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.dim)
            }
            if destination.paused {
                Text("!paused")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.dim)
            }
            Spacer(minLength: 8)
            let chip = theme.chip(for: destination.kind)
            Text(destination.kind.label)
                .font(theme.font(size: 10).weight(.semibold))
                .foregroundStyle(chip.text)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: [chip.fillTop, chip.fillBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? theme.selectionBackground : Color.clear)
        )
        // 14 outer + 14 inner keeps row text on the app-wide 28pt gutter.
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}
