import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared visual language: one accent, one card style, one set of status colors.
enum Theme {
    static let accent = Color(red: 0.15, green: 0.68, blue: 0.78)
    static let cornerRadius: CGFloat = 12
    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.08)

    /// Hues chosen to stay distinct next to each other in light and dark mode.
    /// Ordered so that consecutive slices contrast: teal, purple, orange, green, blue, pink…
    static let chartHues: [Double] = [0.52, 0.76, 0.08, 0.36, 0.61, 0.91, 0.14, 0.46, 0.68, 0.99]

    static func usageColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: accent
        case ..<0.9: .orange
        default: .red
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

extension View {
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

/// A small capsule label, e.g. a risk level or a provider name.
struct Pill: View {
    let title: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct RiskBadge: View {
    let risk: DeletionRisk
    var body: some View {
        Pill(title: risk.title, systemImage: risk.systemImage, color: risk.color)
            .accessibilityLabel(risk.title)
    }
}

/// A thin capacity bar that turns orange and red as a volume fills.
struct CapacityBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(Theme.usageColor(fraction).gradient)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
    }
}

/// A labelled figure for headers and inspectors.
struct StatView: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
                .lineLimit(1)
            HStack(spacing: 3) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Finder-style icons resolved from the file type only, so rows never touch the disk.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: FileNode) -> NSImage {
        let key: String
        let type: UTType
        if node.isDirectory {
            key = "folder"; type = .folder
        } else if node.isSymlink {
            key = "symlink"; type = .symbolicLink
        } else {
            let identifier = node.contentTypeIdentifier ?? UTType.data.identifier
            key = identifier
            type = UTType(identifier) ?? .data
        }
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}

struct FileIconView: View {
    let node: FileNode
    var size: CGFloat = 28

    var body: some View {
        Group {
            if node.isAggregate {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.6)).foregroundStyle(.secondary)
            } else {
                Image(nsImage: FileIcons.icon(for: node)).resizable().interpolation(.high)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
