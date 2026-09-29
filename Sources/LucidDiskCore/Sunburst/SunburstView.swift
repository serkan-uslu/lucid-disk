import SwiftUI
import Foundation
import AppKit

/// Drawing and hit testing share the same responsive geometry.
struct SunburstGeometry {
    let center: CGPoint
    let centerRadius: CGFloat
    let ringWidth: CGFloat
    let ringCount: Int

    init(size: CGSize, ringCount: Int = 3) {
        self.ringCount = max(1, ringCount)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(1, min(size.width, size.height) / 2 - 12)
        centerRadius = radius * 0.30
        ringWidth = radius * 0.70 / CGFloat(self.ringCount)
    }

    func hit(at point: CGPoint, wedges: [Wedge]) -> Wedge? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius > centerRadius, radius < centerRadius + CGFloat(ringCount) * ringWidth else { return nil }
        let level = Int((radius - centerRadius) / ringWidth) + 1
        let angle = (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return wedges.first { $0.level == level && angle >= $0.startDegrees && angle < $0.endDegrees }
    }
}

struct SunburstView: View {
    let focusedNode: FileNode
    let wedges: [Wedge]
    let selectedNode: FileNode?
    let selectedIDs: Set<UUID>
    var onZoomOut: () -> Void
    var onSelect: (FileNode?) -> Void
    var onFocus: (FileNode) -> Void
    var onToggleSelection: (FileNode) -> Void = { _ in }

    @State private var hoveredNodeID: UUID?
    private var hovered: FileNode? { wedges.first { $0.node.id == hoveredNodeID }?.node }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let geometry = SunburstGeometry(size: geo.size, ringCount: wedges.max(by: { $0.level < $1.level })?.level ?? 1)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                                             center: .center, startRadius: 0,
                                             endRadius: min(geo.size.width, geo.size.height) / 2))
                        .padding(8).allowsHitTesting(false)
                    Circle()
                        .fill(Theme.cardFill)
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5))
                        .frame(width: geometry.centerRadius * 1.86, height: geometry.centerRadius * 1.86)
                        .position(geometry.center)
                        .allowsHitTesting(false)
                    Canvas { context, _ in
                        for wedge in wedges {
                            let inner = geometry.centerRadius + CGFloat(wedge.level - 1) * geometry.ringWidth
                            let outer = inner + geometry.ringWidth - 1.5
                            let path = annularSectorPath(
                                center: geometry.center, innerRadius: inner + 1, outerRadius: outer,
                                startDegrees: wedge.startDegrees, endDegrees: wedge.endDegrees
                            )
                            let color = chartColor(seed: wedge.colorSeed, level: wedge.level, aggregate: wedge.node.isAggregate)
                            let selected = selectedIDs.contains(wedge.node.id)
                            let hovered = hoveredNodeID == wedge.node.id
                            let dimmed = hoveredNodeID != nil && !hovered && !selected
                            context.fill(path, with: .color(color.opacity(dimmed ? 0.55 : (hovered || selected ? 1 : 0.88))))
                            // Separate wedges with the window color instead of a dark outline.
                            context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
                            if selected || hovered {
                                context.stroke(path, with: .color(.white.opacity(selected ? 0.95 : 0.6)), lineWidth: 2)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("disk-usage-chart")
                    .accessibilityLabel("Disk usage chart")
                    .accessibilityChildren {
                        ForEach(wedges, id: \.node.id) { wedge in
                            Text(wedge.node.name)
                                .accessibilityValue(ByteCountFormatter.string(fromByteCount: wedge.node.size, countStyle: .file))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { activate(wedge.node) }
                                .accessibilityAction(named: Text("Inspect")) { onSelect(wedge.node) }
                        }
                    }

                    ChartInputSurface(wedges: wedges, onActivate: activate, onToggle: onToggleSelection, onZoomOut: onZoomOut, onHover: { next in
                        if next != hoveredNodeID { hoveredNodeID = next }
                    })
                    .accessibilityHidden(true)

                    Button(action: onZoomOut) {
                        VStack(spacing: 6) {
                            if focusedNode.parent != nil {
                                Image(systemName: "arrow.up").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: focusedNode.size, countStyle: .file))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text(focusedNode.name).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .frame(width: geometry.centerRadius * 1.65, height: geometry.centerRadius * 1.65)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(false)
                    .help("Back to parent folder")
                    .accessibilityLabel("Back to parent folder")
                    .position(geometry.center)
                }
            }
            let shown = hovered ?? selectedNode ?? focusedNode
            HStack(spacing: 12) {
                FileIconView(node: shown, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.name)
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(shown.path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ByteCountFormatter.string(fromByteCount: shown.size, countStyle: .file))
                        .font(.callout.weight(.semibold).monospacedDigit())
                    if shown !== focusedNode, focusedNode.size > 0 {
                        Text((Double(shown.size) / Double(focusedNode.size))
                            .formatted(.percent.precision(.fractionLength(shown.size * 100 < focusedNode.size ? 1 : 0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
            }
            .card(padding: 12)
        }
        .onChange(of: focusedNode.id) { _, _ in hoveredNodeID = nil }
    }

    private func activate(_ node: FileNode) {
        if node.isDirectory || node.isAggregate { onFocus(node) }
        else { onSelect(node) }
    }
}

/// Native mouse events keep chart navigation immediate and avoid gesture conflicts.
private struct ChartInputSurface: NSViewRepresentable {
    let wedges: [Wedge]
    let onActivate: (FileNode) -> Void
    let onToggle: (FileNode) -> Void
    let onZoomOut: () -> Void
    let onHover: (UUID?) -> Void

    func makeNSView(context: Context) -> ChartMouseView {
        let view = ChartMouseView()
        view.identifier = NSUserInterfaceItemIdentifier("chart-input")
        return view
    }

    func updateNSView(_ view: ChartMouseView, context: Context) {
        view.wedges = wedges
        view.onActivate = onActivate
        view.onToggle = onToggle
        view.onZoomOut = onZoomOut
        view.onHover = onHover
    }
}

private final class ChartMouseView: NSView {
    var wedges: [Wedge] = []
    var onActivate: ((FileNode) -> Void)?
    var onToggle: ((FileNode) -> Void)?
    var onZoomOut: (() -> Void)?
    var onHover: ((UUID?) -> Void)?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let geometry = SunburstGeometry(size: bounds.size)
        if hypot(point.x - geometry.center.x, point.y - geometry.center.y) <= geometry.centerRadius {
            onZoomOut?()
            return
        }
        guard let node = node(at: event) else { return }
        // ⌘-click adds a slice to the selection instead of opening it.
        if event.modifierFlags.contains(.command), !node.isAggregate {
            onToggle?(node)
        } else {
            onActivate?(node)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let node = node(at: event)
        onHover?(node?.id)
        (node == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
        NSCursor.arrow.set()
    }

    private func node(at event: NSEvent) -> FileNode? {
        let geometry = SunburstGeometry(size: bounds.size, ringCount: wedges.max(by: { $0.level < $1.level })?.level ?? 1)
        return geometry.hit(at: convert(event.locationInWindow, from: nil), wedges: wedges)?.node
    }
}

private func annularSectorPath(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startDegrees: Double, endDegrees: Double) -> Path {
    var path = Path()
    let start = Angle(degrees: startDegrees)
    let end = Angle(degrees: endDegrees)
    path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
    path.addLine(to: CGPoint(x: center.x + innerRadius * cos(end.radians), y: center.y + innerRadius * sin(end.radians)))
    path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
    path.closeSubpath()
    return path
}

func chartColor(seed: String, level: Int, aggregate: Bool) -> Color {
    if aggregate { return .gray.opacity(0.45) }
    if seed.hasPrefix("rank:"), let rank = Int(seed.dropFirst(5)) {
        let hues = Theme.chartHues
        let depth = Double(max(0, level - 1))
        return Color(hue: hues[rank % hues.count], saturation: 0.58 - depth * 0.08, brightness: 0.90 - depth * 0.05)
    }
    var hash: UInt32 = 2166136261
    for byte in seed.utf8 { hash = (hash ^ UInt32(byte)).multipliedReportingOverflow(by: 16777619).partialValue }
    let hues = Theme.chartHues
    let depth = Double(max(0, level - 1))
    return Color(hue: hues[Int(hash % UInt32(hues.count))],
                 saturation: 0.58 - depth * 0.08,
                 brightness: 0.90 - depth * 0.05)
}
