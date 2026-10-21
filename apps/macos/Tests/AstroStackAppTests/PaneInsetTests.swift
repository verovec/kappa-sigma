import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// The top of each pane stays below the toolbar in a real window on screen (card 0084): nothing is
/// drawn in the band the split view reserves for the toolbar over the detail column, and the
/// pane's header shows right under it. Offscreen hosting views have no toolbar, so only an
/// ordered-front window, cached to pixels, shows the regression.
@MainActor
@Suite(
  "Pane insets — pane tops below the toolbar in real windows", .serialized,
  .enabled(if: NSScreen.main != nil))
struct PaneInsetTests {
  /// Luminance spread (max − min) of the detail column's rows in `rows` (points from the top).
  struct Spread {
    let band: Double
    let below: Double
  }

  /// `window`'s frame drawn to pixels; the detail column is its right half, clear of the sidebar.
  static func spread(of window: NSWindow, inset: CGFloat) throws -> Spread {
    let frame = try #require(window.contentView?.superview)
    let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
    frame.cacheDisplay(in: frame.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsHigh) / frame.bounds.height
    func spread(_ rows: Range<Int>) -> Double {
      var low = 1.0
      var high = 0.0
      for y in rows {
        for x in stride(from: bitmap.pixelsWide / 2, to: bitmap.pixelsWide * 19 / 20, by: 2) {
          guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
          let luma =
            0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent
            + 0.0722 * pixel.blueComponent
          low = min(low, Double(luma))
          high = max(high, Double(luma))
        }
      }
      return high - low
    }
    // A margin of 4 pt around the band edge skips the separator line SwiftUI draws there.
    let top = Int(inset * scale)
    let margin = Int(4 * scale)
    return Spread(
      band: spread(margin..<(top - margin)),
      below: spread((top + margin)..<(top + Int(60 * scale))))
  }

  /// `content` in an on-screen window of `size`, as `ProjectDocument` and `LegacyRunWindow` build
  /// theirs, after SwiftUI laid it out and bridged its toolbar.
  static func show(_ content: NSView, size: NSSize) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: SplitWindow.styleMask,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = content
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    return window
  }

  @Test(
    "nothing of a stage's pane is drawn under the toolbar, its header shows below it",
    .scratchDirectory, arguments: [JourneyStage.data, .stacking])
  func testPaneTopBelowToolbar(_ stage: JourneyStage) throws {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("IC1848.astrostack"))
    defer { try? project.close() }
    try project.store.addSource(kind: .night, path: "/captures/IC1848/2026-10-18")
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    model.select(stage)
    let content = NSHostingView(rootView: ProjectWindowView(model: model).interfaceLocale())
    content.sizingOptions = [.minSize]
    let window = Self.show(content, size: NSSize(width: 960, height: 692))
    defer { window.orderOut(nil) }

    let inset = content.safeAreaInsets.top
    #expect(inset > 20, "the split view reserves the toolbar: \(inset) pt")
    let spread = try Self.spread(of: window, inset: inset)
    #expect(spread.band < 0.05, "\(stage): content drawn under the toolbar (\(spread.band))")
    #expect(spread.below > 0.3, "\(stage): the header shows below the toolbar (\(spread.below))")
  }
}
