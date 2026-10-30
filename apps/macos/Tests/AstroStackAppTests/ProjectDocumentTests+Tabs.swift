import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// A second project opens as a tab of the first, whatever « Prefer tabs » says in System
  /// Settings (its default tabs only in full screen); viewers and legacy runs stay apart.
  @Test("two open projects' windows prefer tabs and share one tab group", .scratchDirectory)
  func testProjectDocument_window_opensAsTab() throws {
    let documents = try ["M31", "IC1848"].map { name in
      let url = try ScratchDirectory.url.appendingPathComponent("\(name).astrostack")
      try ProjectPackage.create(at: url).close()
      let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
      document.makeWindowControllers()
      return document
    }
    defer { documents.forEach { $0.close() } }

    let windows = try documents.map { try #require($0.windowControllers.first?.window) }
    #expect(windows[0] !== windows[1])
    for window in windows {
      #expect(window.tabbingMode == .preferred)
      #expect(window.tabbingIdentifier == ProjectDocument.tabbingIdentifier)
    }
  }

  /// The tab bar's « + » is answered by the project, before `NSDocumentController` could open an
  /// untitled package past the naming sheet.
  @Test("the tab bar's + is New Project…, not an untitled document")
  func testProjectDocument_newWindowForTab_answeredByProject() throws {
    let document = try ProjectDocument(type: Self.type)
    defer { document.close() }
    #expect(document.responds(to: #selector(NSResponder.newWindowForTab(_:))))
  }
}
