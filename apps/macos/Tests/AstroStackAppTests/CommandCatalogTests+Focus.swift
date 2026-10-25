import AppKit
import AstroStackApp
import Foundation
import Testing

extension CommandCatalogTests {
  /// Card 0127: the full-screen image and the zoom steps, View menu, Studio stage; ⌃⌘F stays the
  /// system's window full screen, ⌘0 / ⌘1 Fit and Actual Pixels.
  @Test(
    "testFocusAndZoomCommands",
    arguments: [
      (
        "view.focusImage", "f", NSEvent.ModifierFlags([.command, .shift]).rawValue,
        "Image en plein écran"
      ),
      ("view.zoomIn", "=", NSEvent.ModifierFlags.command.rawValue, "Zoom avant"),
      ("view.zoomOut", "-", NSEvent.ModifierFlags.command.rawValue, "Zoom arrière"),
    ])
  func testFocusAndZoomCommands(id: String, key: String, modifiers: UInt, french: String) throws {
    let command = try #require(CommandCatalog.command(id))
    #expect(command.menu == .view && command.stage == .studio && command.action != nil)
    #expect(command.shortcut?.key == key)
    #expect(command.shortcut?.flags == NSEvent.ModifierFlags(rawValue: modifiers))
    let others = CommandCatalog.commands.filter { $0.id != id }.compactMap(\.shortcut)
    #expect(!others.contains(try #require(command.shortcut)), "bound once")
    var title = command.title(locale: Locale(identifier: "fr"))
    title.locale = Locale(identifier: "fr")
    #expect(String(localized: title) == french)
  }
}
