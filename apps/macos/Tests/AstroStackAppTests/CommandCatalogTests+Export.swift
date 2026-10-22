import AppKit
import AstroStackApp
import Testing

extension CommandCatalogTests {
  @Test("Export… is ⇧⌘E in the File menu, on the Export stage (⌘E is the Studio's Apply)")
  func testExportCommand() throws {
    let command = try #require(CommandCatalog.command("file.export"))
    #expect(command.menu == .file && command.stage == .export)
    #expect(command.action == "showExport:")
    #expect(command.shortcut?.symbols == "⇧⌘E")
    #expect(CommandCatalog.command("studio.apply")?.shortcut?.symbols == "⌘E")
  }
}
