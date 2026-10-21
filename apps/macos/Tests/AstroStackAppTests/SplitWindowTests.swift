import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import TestSupport
import Testing

/// Windows that host a `NavigationSplitView` let their content run under the title bar, as a
/// SwiftUI window does: the split view then insets its columns by the toolbar once. Without
/// `.fullSizeContentView` the inset is counted twice and the top of every pane is drawn under the
/// toolbar band, blurred (PO screenshot 2026-10-21, card 0084).
@MainActor
@Suite("Split-view windows — content under the title bar, inset once")
struct SplitWindowTests {
  @Test("the shared style lets content run under the title bar")
  func testStyleMaskIsFullSizeContent() {
    #expect(SplitWindow.styleMask.contains(.fullSizeContentView))
    #expect(
      SplitWindow.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable]))
  }

  @Test("the project window uses it", .scratchDirectory)
  func testProjectWindowIsFullSizeContent() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("IC1848.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectDocumentTests.type)
    document.makeWindowControllers()
    defer { document.close() }
    let window = try #require(document.windowControllers.first?.window)
    #expect(window.styleMask == SplitWindow.styleMask)
  }

  @Test(
    "the legacy run window uses it", .scratchDirectory,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testLegacyRunWindowIsFullSizeContent() async throws {
    let folder = try LegacyRunWindowTests.run(in: try ScratchDirectory.url)
    let controller = try await LegacyRunWindow.open(folder, into: nil)
    defer { controller.window?.close() }
    #expect(controller.window?.styleMask == SplitWindow.styleMask)
  }
}
