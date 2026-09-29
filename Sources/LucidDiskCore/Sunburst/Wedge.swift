import Foundation

/// One angular slice of the sunburst: a node, which ring it belongs to
/// (level, 1-based), its angular span in degrees, and a color seed shared
/// by an entire top-level branch so the whole subtree reads as one color.
struct Wedge {
    let node: FileNode
    let level: Int
    let startDegrees: Double
    let endDegrees: Double
    let colorSeed: String
}

/// Lays out `focusedNode`'s descendants as concentric rings. Children below
/// `minFraction` of their parent's size are grouped into a single "Other"
/// wedge instead of being drawn as unreadable slivers.
func computeWedges(focusedNode: FileNode, maxLevels: Int = 3, minFraction: Double = 0.004) -> [Wedge] {
    var wedges: [Wedge] = []

    func recurse(_ node: FileNode, level: Int, start: Double, end: Double, colorSeed: String) {
        let children = node.isAggregate ? node.aggregatedChildren : node.children
        guard level < maxLevels, node.size > 0, !children.isEmpty else { return }

        let total = Double(node.size)
        let span = end - start
        let candidates = children.filter { $0.size > 0 }.sorted(by: chartOrder)

        var kept: [FileNode] = []
        var leftoverSize: Int64 = 0
        var leftoverChildren: [FileNode] = []
        for child in candidates {
            // Threshold is relative to the full chart, not a tiny parent slice.
            if span * Double(child.size) / total >= 360 * minFraction {
                kept.append(child)
            } else {
                leftoverSize += child.size
                leftoverChildren.append(child)
            }
        }

        var cursor = start
        for (rank, child) in kept.enumerated() {
            let fraction = Double(child.size) / total
            let childSpan = span * fraction
            // Top-level slices take palette colors in size order so neighbours never share a hue.
            let childSeed = level == 0 ? paletteSeed(rank) : colorSeed
            wedges.append(Wedge(node: child, level: level + 1, startDegrees: cursor, endDegrees: cursor + childSpan, colorSeed: childSeed))
            if child.isDirectory {
                recurse(child, level: level + 1, start: cursor, end: cursor + childSpan, colorSeed: childSeed)
            }
            cursor += childSpan
        }

        if leftoverSize > 0 {
            let fraction = Double(leftoverSize) / total
            let childSpan = span * fraction
            let agg = FileNode(name: String(localized: "Other"), path: node.path, isDirectory: false, size: leftoverSize)
            agg.isAggregate = true
            agg.aggregatedChildren = leftoverChildren
            agg.parent = node
            let childSeed = level == 0 ? "other-\(node.path)" : colorSeed
            wedges.append(Wedge(node: agg, level: level + 1, startDegrees: cursor, endDegrees: cursor + childSpan, colorSeed: childSeed))
        }
    }

    recurse(focusedNode, level: 0, start: 0, end: 360, colorSeed: focusedNode.path)
    return wedges
}

/// Largest first, name as a stable tie-breaker; the file list uses the same order for colors.
func chartOrder(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
    lhs.size == rhs.size ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.size > rhs.size
}

func paletteSeed(_ rank: Int) -> String { "rank:\(rank)" }

/// Palette rank of each positive-size child, matching the chart's top-level colors.
func paletteRanks(of children: [FileNode]) -> [UUID: Int] {
    let ordered = children.filter { $0.size > 0 }.sorted(by: chartOrder)
    return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
}
