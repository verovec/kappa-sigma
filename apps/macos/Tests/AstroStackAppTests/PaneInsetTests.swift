import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import TestSupport
import Testing

/// The top of each pane stays below the toolbar in the real windows, on screen (card 0084):
/// nothing is drawn in the band the split view reserves for the toolbar over the detail column,
/// and the pane shows right under it. Offscreen hosting views have no toolbar, so only an
/// ordered-front window, cached to pixels, shows the regression.
///
/// The band is sampled over the right half of the window, where no toolbar item sits today: a card
/// that adds trailing toolbar items narrows the sampled columns.
@MainActor
@Suite(
  "Pane insets — pane tops below the toolbar in real windows", .serialized,
  .enabled(if: NSScreen.main != nil))
struct PaneInsetTests {
  /// Luminance spread (max − min) of the right half of the window, in the toolbar band and in the
  /// 60 pt under it.
  struct Spread {
    let band: Double
    let below: Double
  }

  /// Orders `window` front and waits — bounded — for SwiftUI to bridge the toolbar and inset the
  /// content; returns the inset.
  static func show(_ window: NSWindow) throws -> CGFloat {
    window.appearance = NSAppearance(named: .darkAqua)
    window.orderFrontRegardless()
    let content = try #require(window.contentView)
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline && (window.toolbar == nil || content.safeAreaInsets.top == 0) {
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    // One more pass once the inset is known, so the panes are laid out against it.
    content.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    return content.safeAreaInsets.top
  }

  /// `window`'s frame drawn to pixels and measured around `inset`.
  static func spread(of window: NSWindow, inset: CGFloat) throws -> Spread {
    let frame = try #require(window.contentView?.superview)
    let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
    frame.cacheDisplay(in: frame.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsHigh) / frame.bounds.height
    func spread(_ rows: Range<Int>) -> Double {
      var low = 1.0
      var high = 0.0
      for y in stride(from: rows.lowerBound, to: rows.upperBound, by: 2) {
        for x in stride(from: bitmap.pixelsWide / 2, to: bitmap.pixelsWide * 19 / 20, by: 3) {
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
    // A margin of 4 pt around the band's edge skips the separator line SwiftUI draws there.
    let top = Int(inset * scale)
    let margin = Int(4 * scale)
    return Spread(
      band: spread(margin..<(top - margin)),
      below: spread((top + margin)..<(top + Int(60 * scale))))
  }

  @Test(
    "nothing of a stage's pane is drawn under the toolbar, its header shows below it",
    .scratchDirectory, arguments: [JourneyStage.data, .stacking])
  func testProjectPaneBelowToolbar(_ stage: JourneyStage) throws {
    let url = try ScratchDirectory.url.appendingPathComponent("IC1848.astrostack")
    let project = try ProjectPackage.create(at: url)
    try project.store.addSource(kind: .night, path: "/captures/IC1848/2026-10-18")
    // The window restores the stage last shown (card 0076).
    try project.store.setSetting("workspace.stage", to: stage.rawValue)
    try project.close()
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectDocumentTests.type)
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)

    let inset = try Self.show(window)
    try #require(inset > 20, "the split view reserves the toolbar: \(inset) pt")
    let spread = try Self.spread(of: window, inset: inset)
    #expect(spread.band < 0.05, "\(stage): content drawn under the toolbar (\(spread.band))")
    #expect(spread.below > 0.3, "\(stage): the header shows below the toolbar (\(spread.below))")
  }

  @Test(
    "nothing of the legacy run's viewer or panel is drawn under the toolbar", .scratchDirectory,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testLegacyRunBelowToolbar() async throws {
    let folder = try LegacyRunWindowTests.run(in: try ScratchDirectory.url)
    let controller = try await LegacyRunWindow.open(folder, into: nil)
    defer { controller.window?.close() }
    let window = try #require(controller.window)

    let inset = try Self.show(window)
    try #require(inset > 20, "the split view reserves the toolbar: \(inset) pt")
    let spread = try Self.spread(of: window, inset: inset)
    // The viewer is a Metal layer, which `cacheDisplay` does not draw: only the band is checked.
    #expect(spread.band < 0.05, "content drawn under the toolbar (\(spread.band))")
  }
}
