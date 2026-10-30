import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// The project window's minimum is set once, never republished by SwiftUI on a layout pass:
  /// that feedback, between the split view's column minimums, looped when a window was enlarged
  /// (crashes of 29/10).
  @Test("the project window has a fixed minimum size; SwiftUI sizes nothing", .scratchDirectory)
  func testProjectDocument_window_fixedMinimumSize() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    document.makeWindowControllers()
    defer { document.close() }

    let window = try #require(document.windowControllers.first?.window)
    try #require(window.contentView).layoutSubtreeIfNeeded()
    #expect(window.contentMinSize == NSSize(width: 640, height: 452))
    #expect(window.contentMinSize == SplitWindow.contentMinSize)
  }
}
