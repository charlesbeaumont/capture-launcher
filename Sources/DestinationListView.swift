import SwiftUI

/// Fixed-viewport destination list: always `Theme.listRows` rows tall so the
/// panel never resizes while filtering; unfilled rows stay blank. Selection
/// is an inverted block.
struct DestinationListView: View {
    let ranked: [RankedDestination]
    let selectionIndex: Int
    let theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ranked.prefix(Theme.listRows).enumerated()), id: \.element.id) { index, item in
                row(item.destination, selected: index == selectionIndex)
            }
            Spacer(minLength: 0)
        }
        .frame(height: CGFloat(Theme.listRows) * Theme.rowHeight, alignment: .top)
    }

    private func row(_ destination: Destination, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(destination.leafName)
                .font(theme.font(size: 14))
                .foregroundStyle(selected ? theme.selectionForeground : theme.foreground)
                .lineLimit(1)
            if !destination.registered {
                Text("·new")
                    .font(theme.font(size: 11))
                    .foregroundStyle(selected ? theme.selectionForeground.opacity(0.7) : theme.dim)
            }
            if destination.paused {
                Text("!paused")
                    .font(theme.font(size: 11))
                    .foregroundStyle(selected ? theme.selectionForeground.opacity(0.7) : theme.dim)
            }
            Spacer(minLength: 8)
            Text(destination.kind.label)
                .font(theme.font(size: 10).weight(.semibold))
                .foregroundStyle(theme.badgeText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.badgeColor(for: destination.kind))
                )
        }
        .padding(.horizontal, 28)
        .frame(height: Theme.rowHeight)
        .background(selected ? theme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
    }
}
