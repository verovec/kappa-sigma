import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// The project window's minimum is set once, never republished by SwiftUI on a layout pass:
  /// that feedback, between the split view's column minimums, looped when a window was enlarged
  /// (crashes of 29/10). It holds every column at its minimum, the guide's included (card 0176).
  @Test("the project window has a fixed minimum size; SwiftUI sizes nothing", .scratchDirectory)
  func testProjectDocument_window_fixedMinimumSize() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    document.makeWindowControllers()
    defer { document.close() }

    let window = try #require(document.windowControllers.first?.window)
    try #require(window.contentView).layoutSubtreeIfNeeded()
    #expect(window.contentMinSize == NSSize(width: 1122, height: 452))
    #expect(window.contentMinSize == SplitWindow.contentMinSize)
  }

  /// Card 0176: a frame restored from a build with a smaller minimum is grown back to it — a
  /// window narrower than its columns is the layout loop the minimum prevents.
  @Test(
    "a restored frame under the minimum is grown to it (restoreState calls growToMinimum)",
    .scratchDirectory)
  func testProjectDocument_window_restoredFrameClamped() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)

    // As a restored frame from a build whose minimum was 640 × 452: `setFrame` lets it through.
    window.setFrame(
      window.frameRect(
        forContentRect: SplitWindow.contentRect(panes: NSSize(width: 960, height: 640))),
      display: false)
    let project = try #require(window as? ProjectWindow)
    project.growToMinimum()

    let content = window.contentRect(forFrameRect: window.frame).size
    #expect(content.width >= window.contentMinSize.width, "\(content)")
    #expect(content.height >= window.contentMinSize.height, "\(content)")
    #expect(
      SplitWindow.clamped(NSSize(width: 960, height: 2000), to: NSSize(width: 1122, height: 452))
        == NSSize(width: 1122, height: 2000))
  }
}
