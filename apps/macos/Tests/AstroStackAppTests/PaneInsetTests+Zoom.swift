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
  /// Turns the run loop (AppKit's display cycle) and the main actor (the workspace's load) until
  /// `done` holds or `seconds` pass, by the clock.
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

  @Test(
    "a Studio window zooms there and back, then takes every width from the minimum to the screen",
    .scratchDirectory, .timeLimit(.minutes(3)),
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testZoomAndResize_studio() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    try ProjectTests.addStudioStack(fixture)
    let model = fixture.window
    // The window the document builds, on screen before the Studio arrives in it.
    let window = ProjectWindow.make(model: model, projects: .empty)
    defer { window.close() }
    let screen = try #require(window.screen ?? NSScreen.main)
    window.center()
    window.orderFrontRegardless()
    let content = try #require(window.contentView)
    // Driven from here, not left to the window's task: the load is awaited, then bounded by the
    // clock, whatever the machine's load (the window's own call keeps the same workspace).
    await model.openStudio()
    await Self.spin(60) { model.workspace != nil || model.error != nil }
    try #require(model.workspace != nil, "the workspace loads: \(String(describing: model.error))")
    await Self.spin(10) { StudioViewsTests.surface(in: content) != nil }
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
      window.setFrame(NSRect(origin: visible.origin, size: size), display: true, animate: false)
      await Self.spin(0.05)
    }
    #expect(content.frame.width >= window.contentMinSize.width)
  }
}
