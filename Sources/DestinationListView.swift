import SwiftUI

/// Fixed-viewport destination list: always `Theme.listRows` rows tall so the
/// panel never resizes while filtering; unfilled rows stay blank. Selection is
/// a flat full-bleed accent wash — no radius, no inset (Gyors' ResultRow).
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
                .font(theme.font(size: 14).weight(.medium))
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
                .font(theme.font(size: 11).weight(.semibold))
                .foregroundStyle(chip.text)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: [chip.fillTop, chip.fillBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        }
        // One 20pt gutter, same as the query row above, so the leaf name lines
        // up with the typed text. No outer padding: the fill must reach both
        // panel edges.
        .padding(.horizontal, 20)
        .frame(height: Theme.rowHeight)
        .background(selected ? theme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
    }
}
