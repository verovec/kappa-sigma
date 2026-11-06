import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import TestSupport
import Testing

/// Card 0176: a project window on a loaded Studio is zoomed to the screen and back, as a
/// double-click on its title bar does, then resized step by step from its minimum to the screen —
/// where the crashes of 29/10 and 06/11 raised « more Update Constraints in Window passes than
/// there are views ». A loop aborts the test process, so a regression shows as a crash of this
/// suite. Only an ordered-front window runs AppKit's display cycle; it shares the serialized suite
/// of the other ordered-front windows so no two real windows are on screen at once.
extension PaneInsetTests {
  /// Turns the run loop and the main actor (the Studio loads in a task the window owns) until
  /// `done` holds or `seconds` pass.
  static func spin(_ seconds: TimeInterval, until done: () -> Bool = { false }) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline && !done() {
      turn()
      await Task.yield()
    }
  }

  /// One short turn of the run loop: AppKit's display cycle, the zoom's animation.
  static func turn() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  }

  /// A project whose window restores the Studio on one readable stack.
  static func studioProject(in scratch: URL) throws -> URL {
    let url = scratch.appendingPathComponent("M31.astrostack")
    let project = try ProjectPackage.create(at: url)
    let output = url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try ProjectTests.writeBundle(in: output, runID: "A")
    _ = try project.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    try project.store.setSetting("workspace.stage", to: JourneyStage.studio.rawValue)
    try project.close()
    return url
  }

  @Test(
    "a Studio window zooms there and back, then takes every width from the minimum to the screen",
    .scratchDirectory, .timeLimit(.minutes(3)),
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testZoomAndResize_studio() async throws {
    let url = try Self.studioProject(in: try ScratchDirectory.url)
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectDocumentTests.type)
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)
    let screen = try #require(window.screen ?? NSScreen.main)
    window.orderFrontRegardless()
    let content = try #require(window.contentView)
    // Generous: the whole suite runs in parallel and the Studio loads in the window's own task.
    await Self.spin(60) { StudioViewsTests.surface(in: content) != nil }
    try #require(StudioViewsTests.surface(in: content) != nil, "the Studio's image is shown")

    let opening = window.frame
    window.zoom(nil)
    await Self.spin(1.5)
    #expect(window.frame.width > opening.width, "zoomed to the screen")
    window.zoom(nil)
    await Self.spin(1.5)

    let minimum = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
    ).size
    let visible = screen.visibleFrame
    for step in 0...16 {
      let share = CGFloat(step) / 16
      let size = NSSize(
        width: minimum.width + (visible.width - minimum.width) * share,
        height: minimum.height + (visible.height - minimum.height) * share)
      window.setFrame(
        NSRect(origin: visible.origin, size: size), display: true, animate: false)
      await Self.spin(0.05)
    }
    #expect(content.frame.width >= window.contentMinSize.width)
  }
}
