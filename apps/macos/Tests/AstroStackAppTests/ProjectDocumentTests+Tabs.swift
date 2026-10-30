import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// A second project opens as a tab of the first, whatever « Prefer tabs » says in System
  /// Settings (its default tabs only in full screen); viewers and legacy runs stay apart.
  @Test("project windows prefer tabs and share one tab group", .scratchDirectory)
  func testProjectDocument_window_opensAsTab() throws {
    var windows: [NSWindow] = []
    for name in ["M31", "IC1848"] {
      let url = try ScratchDirectory.url.appendingPathComponent("\(name).astrostack")
      try ProjectPackage.create(at: url).close()
      let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
      document.makeWindowControllers()
      defer { document.close() }
      windows.append(try #require(document.windowControllers.first?.window))
    }

    for window in windows {
      #expect(window.tabbingMode == .preferred)
      #expect(window.tabbingIdentifier == ProjectDocument.tabbingIdentifier)
    }
  }
}
