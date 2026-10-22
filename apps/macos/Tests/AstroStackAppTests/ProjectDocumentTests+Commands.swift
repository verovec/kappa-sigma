import AppKit
import AstroStackApp
import Testing

extension ProjectDocumentTests {
  /// Without a window the Studio and Tri commands do nothing and their menu items are off:
  /// Apply needs an open panel on the Studio stage, keep / reject / continue the Tri stage.
  @Test("Studio and Tri commands without a window: no effect, menu items off", .scratchDirectory)
  func testCommandsWithoutWindow() throws {
    let document = try ProjectDocument(type: Self.type)
    defer { document.close() }
    document.showGuide(nil)
    document.applyProcess(nil)
    document.blinkPrevious(nil)
    document.blinkNext(nil)
    document.keepFrame(nil)
    document.rejectFrame(nil)
    document.continueStacking(nil)
    let off: [Selector] = [
      #selector(ProjectDocument.applyProcess(_:)), #selector(ProjectDocument.keepFrame(_:)),
      #selector(ProjectDocument.rejectFrame(_:)), #selector(ProjectDocument.blinkNext(_:)),
      #selector(ProjectDocument.blinkPrevious(_:)),
      #selector(ProjectDocument.continueStacking(_:)),
    ]
    for action in off {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      #expect(!document.validateUserInterfaceItem(item), "\(action)")
    }
    let save = NSMenuItem(
      title: "", action: #selector(NSDocument.save(_:)), keyEquivalent: "")
    _ = document.validateUserInterfaceItem(save)
  }
}
