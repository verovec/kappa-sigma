import AppKit
import AstroStackApp
import Testing

extension CommandCatalogTests {
  /// Card 0105: rotate and flip the shown image from the keyboard (⌘R stays Open Run…, ⌥⌘R Run
  /// Pipeline); Edit menu, Studio stage. They edit the geometry panel, Apply stays ⌘E (R2).
  @Test(
    "testGeometryCommands",
    arguments: [
      ("studio.rotateClockwise", "r", NSEvent.ModifierFlags([.command, .shift]).rawValue),
      (
        "studio.rotateCounterclockwise", "r",
        NSEvent.ModifierFlags([.command, .option, .shift]).rawValue
      ),
      ("studio.flipHorizontally", "h", NSEvent.ModifierFlags([.command, .shift]).rawValue),
      ("studio.flipVertically", "v", NSEvent.ModifierFlags([.command, .shift]).rawValue),
    ])
  func testGeometryCommands(id: String, key: String, modifiers: UInt) throws {
    let flags = NSEvent.ModifierFlags(rawValue: modifiers)
    let command = try #require(CommandCatalog.command(id))
    #expect(command.menu == .edit && command.stage == .studio)
    #expect(command.shortcut?.key == key && command.shortcut?.flags == flags)
    #expect(command.action != nil)
    let others = CommandCatalog.commands.filter { $0.id != id }.compactMap(\.shortcut)
    #expect(!others.contains(try #require(command.shortcut)), "bound once")
  }
}
