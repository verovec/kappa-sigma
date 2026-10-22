import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// File › Export… shows the Export stage; it is off until a stack gives the stage an image.
  @Test(
    "Export… is off without a window or a stack, on once the project has a stack", .scratchDirectory
  )
  func testExportCommandFollowsTheStage() throws {
    let item = NSMenuItem(
      title: "", action: #selector(ProjectDocument.showExport(_:)), keyEquivalent: "")
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let empty = try ProjectDocument(contentsOf: url, ofType: Self.type)
    empty.showExport(nil)
    #expect(!empty.validateUserInterfaceItem(item), "no window")
    empty.makeWindowControllers()
    #expect(!empty.validateUserInterfaceItem(item), "no stack: Export needs one")
    empty.close()

    let stacked = try ProjectPackage.open(at: url)
    try stacked.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
    try stacked.close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    defer { document.close() }
    document.makeWindowControllers()
    #expect(document.validateUserInterfaceItem(item))
    document.showExport(nil)
  }
}
