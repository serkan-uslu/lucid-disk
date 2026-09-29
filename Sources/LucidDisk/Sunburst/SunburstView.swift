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
    var onZoomOut: () -> Void
    var onSelect: (FileNode?) -> Void
    var onFocus: (FileNode) -> Void

    @State private var hoveredNodeID: UUID?
    private var hovered: FileNode? { wedges.first { $0.node.id == hoveredNodeID }?.node }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let geometry = SunburstGeometry(size: geo.size, ringCount: wedges.max(by: { $0.level < $1.level })?.level ?? 1)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.cyan.opacity(0.07), .clear],
                                             center: .center, startRadius: 0,
                                             endRadius: min(geo.size.width, geo.size.height) / 2))
                        .padding(8).allowsHitTesting(false)
                    Canvas { context, _ in
                        for wedge in wedges {
                            let inner = geometry.centerRadius + CGFloat(wedge.level - 1) * geometry.ringWidth
                            let outer = inner + geometry.ringWidth - 1.5
                            let path = annularSectorPath(
                                center: geometry.center, innerRadius: inner + 1, outerRadius: outer,
                                startDegrees: wedge.startDegrees, endDegrees: wedge.endDegrees
                            )
                            let color = chartColor(seed: wedge.colorSeed, level: wedge.level, aggregate: wedge.node.isAggregate)
                            let active = selectedNode?.id == wedge.node.id || hoveredNodeID == wedge.node.id
                            context.fill(path, with: .linearGradient(
                                Gradient(colors: [color, color.opacity(active ? 1 : 0.76)]),
                                startPoint: .zero, endPoint: CGPoint(x: geo.size.width, y: geo.size.height)
                            ))
                            context.stroke(path, with: .color(active ? .white.opacity(0.95) : .black.opacity(0.18)),
                                           lineWidth: active ? 2 : 0.5)
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

                    ChartInputSurface(wedges: wedges, onActivate: activate, onZoomOut: onZoomOut, onHover: { next in
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
            HStack(spacing: 10) {
                Image(systemName: (hovered ?? selectedNode)?.isDirectory == true ? "folder.fill" : "circle.grid.2x2")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text((hovered ?? selectedNode)?.name ?? focusedNode.name)
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text((hovered ?? selectedNode)?.path ?? focusedNode.path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Text(ByteCountFormatter.string(fromByteCount: (hovered ?? selectedNode ?? focusedNode).size, countStyle: .file))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            }
            .padding(14)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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
        view.onZoomOut = onZoomOut
        view.onHover = onHover
    }
}

private final class ChartMouseView: NSView {
    var wedges: [Wedge] = []
    var onActivate: ((FileNode) -> Void)?
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
        if let node = node(at: event) { onActivate?(node) }
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
    var hash: UInt32 = 2166136261
    for byte in seed.utf8 { hash = (hash ^ UInt32(byte)).multipliedReportingOverflow(by: 16777619).partialValue }
    let hues: [Double] = [0.50, 0.57, 0.64, 0.72, 0.79, 0.43, 0.09]
    return Color(hue: hues[Int(hash % UInt32(hues.count))],
                 saturation: 0.62 - Double(level - 1) * 0.07,
                 brightness: 0.91 - Double(level - 1) * 0.07)
}
