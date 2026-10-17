import AppKit
import SwiftUI
import XCTest
@testable import LucidDiskCore

final class ScanProgressRenderingTests: XCTestCase {
    func testAnimatedArcsStayInsideTheirSquareAndRotateAroundItsCenter() {
        let size = CGSize(width: 64, height: 64)
        let canvas = CGRect(origin: .zero, size: size)
        for ring in 0..<2 {
            var sweptBounds = CGRect.null
            // Sample several complete rotations at the same large timestamp
            // magnitude the running TimelineView uses, including round caps.
            for frame in 0...600 {
                let path = ScanningRings.arc(index: ring, time: 800_000_000 + Double(frame) / 30, size: size)
                let bounds = path.strokedPath(StrokeStyle(lineWidth: 4, lineCap: .round)).boundingRect
                XCTAssertFalse(bounds.isEmpty)
                XCTAssertTrue(canvas.contains(bounds), "Ring \(ring) escaped its layout slot at frame \(frame): \(bounds)")
                sweptBounds = sweptBounds.union(bounds)
            }
            XCTAssertEqual(sweptBounds.midX, canvas.midX, accuracy: 0.1)
            XCTAssertEqual(sweptBounds.midY, canvas.midY, accuracy: 0.1)
            XCTAssertEqual(sweptBounds.width, sweptBounds.height, accuracy: 0.1)
        }
    }

    func testElapsedTimeKeepsMinuteAndHourBoundariesReadable() {
        XCTAssertEqual(ScanElapsedTime.format(0), "00:00")
        XCTAssertEqual(ScanElapsedTime.format(59.9), "00:59")
        XCTAssertEqual(ScanElapsedTime.format(60), "01:00")
        XCTAssertEqual(ScanElapsedTime.format(3_599), "59:59")
        XCTAssertEqual(ScanElapsedTime.format(3_600), "1:00:00")
        XCTAssertEqual(ScanElapsedTime.format(36_000), "10:00:00")
        XCTAssertEqual(ScanElapsedTime.format(-1), "00:00")
        XCTAssertEqual(ScanElapsedTime.format(.nan), "00:00")
        XCTAssertEqual(ScanElapsedTime.format(.infinity), "00:00")
    }

    @MainActor
    func testMetricColumnsDoNotMoveWhenCountsGainDigitsOrAllocationChangesUnits() throws {
        for width in [CGFloat(340), 620] {
            let samples: [(Int, Int64)] = [(0, 0), (999, 999), (1_000, 1_000),
                                          (9_999_999, 1_500_000_000_000)]
            var baseline: Data?
            for (count, bytes) in samples {
                // The caption band sits below the fixed-height counters.
                // Compare actual rendered
                // pixels rather than a duplicate of SwiftUI's layout calculation.
                let captions = try captionPixels(count: count, bytes: bytes, width: width)
                if let baseline {
                    XCTAssertEqual(captions, baseline, "Metric captions moved when counters changed at width \(width)")
                } else {
                    baseline = captions
                }
            }
        }
    }

    /// Rendering this pure SwiftUI subtree avoids showing a window or relying on
    /// accessibility trees, which the system omits for unordered test windows.
    @MainActor
    private func captionPixels(count: Int, bytes: Int64, width: CGFloat) throws -> Data {
        let view = ScanProgressMetrics(count: count, bytes: bytes)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
            .frame(width: width, height: 120)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        XCTAssertEqual(bitmap.pixelsWide, Int(width))
        XCTAssertEqual(bitmap.pixelsHigh, 120)
        var result = Data()
        var visibleTextPixels = [0, 0]
        for y in bitmap.pixelsHigh * 3 / 5..<bitmap.pixelsHigh - 20 {
            for x in 12..<bitmap.pixelsWide - 12 {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                for value in [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent] {
                    result.append(UInt8(clamping: Int((value * 255).rounded())))
                }
                if color.redComponent > 0.4 && color.greenComponent > 0.4 && color.blueComponent > 0.4 {
                    visibleTextPixels[x < bitmap.pixelsWide / 2 ? 0 : 1] += 1
                }
            }
        }
        for count in visibleTextPixels {
            XCTAssertGreaterThan(count, 20, "Each caption comparison must contain rendered text, not a blank image")
        }
        return result
    }
}
