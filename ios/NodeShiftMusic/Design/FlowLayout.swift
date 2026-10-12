import SwiftUI

private struct FlowSpacingAfterKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    func flowSpacingAfter(_ value: CGFloat) -> some View {
        layoutValue(key: FlowSpacingAfterKey.self, value: value)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func gap(after index: Int, in subviews: Subviews) -> CGFloat {
        subviews[index][FlowSpacingAfterKey.self] ?? spacing
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let lead = current.indices.last.map { gap(after: $0, in: subviews) } ?? 0
            let needed = current.indices.isEmpty ? size.width : current.width + lead + size.width
            if !current.indices.isEmpty && needed > maxWidth + 0.5 {
                result.append(current)
                current = Row()
            }
            let previousGap = current.indices.last.map { gap(after: $0, in: subviews) } ?? 0
            current.width = current.indices.isEmpty ? size.width : current.width + previousGap + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            result.append(current)
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let laidOut = rows(for: subviews, maxWidth: maxWidth)
        let width = laidOut.map { $0.width }.max() ?? 0
        let height = laidOut.map { $0.height }.reduce(0, +) + CGFloat(max(0, laidOut.count - 1)) * lineSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laidOut = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in laidOut {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + gap(after: index, in: subviews)
            }
            y += row.height + lineSpacing
        }
    }
}
