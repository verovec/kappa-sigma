import AppKit
import AstroStackApp
import Testing

@MainActor
@Suite("MainMenu: the document commands reach AppKit's document machinery")
struct MainMenuTests {
  struct Item: Sendable, CustomTestStringConvertible {
    let menu: String
    let title: String
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: String
    var testDescription: String { "\(menu) › \(title)" }
  }

  nonisolated static let items: [Item] = [
    Item(menu: "File", title: "New Project", key: "n", modifiers: .command, action: "newDocument:"),
    Item(menu: "File", title: "Open…", key: "o", modifiers: .command, action: "openDocument:"),
    Item(menu: "File", title: "Close", key: "w", modifiers: .command, action: "performClose:"),
    Item(menu: "File", title: "Save", key: "s", modifiers: .command, action: "saveDocument:"),
    Item(
      menu: "File", title: "Save As…", key: "s", modifiers: [.command, .shift],
      action: "saveDocumentAs:"),
    Item(
      menu: "AstroStack", title: "Quit AstroStack", key: "q", modifiers: .command,
      action: "terminate:"),
    Item(
      menu: "File", title: "Open Image…", key: "O", modifiers: .command, action: "openImage:"),
    Item(menu: "File", title: "Open Run…", key: "r", modifiers: .command, action: "openRun:"),
    Item(menu: "View", title: "Zoom to Fit", key: "0", modifiers: .command, action: "zoomToFit:"),
    Item(
      menu: "View", title: "Actual Pixels", key: "1", modifiers: .command,
      action: "zoomToActualSize:"),
    Item(menu: "Edit", title: "Undo", key: "z", modifiers: .command, action: "undo:"),
    Item(
      menu: "Window", title: "Minimize", key: "m", modifiers: .command,
      action: "performMiniaturize:"),
  ]

  @Test("each command has its title, shortcut and action", arguments: items)
  func testMainMenu_item(_ expected: Item) throws {
    let menu = try #require(
      MainMenu.make().items.first { $0.submenu?.title == expected.menu }?.submenu)
    let item = try #require(menu.items.first { $0.title == expected.title })
    #expect(item.keyEquivalent == expected.key)
    #expect(item.keyEquivalentModifierMask == expected.modifiers)
    #expect(item.action.map(NSStringFromSelector) == expected.action)
  }

  @Test("menus appear in the standard order")
  func testMainMenu_order() {
    #expect(
      MainMenu.make().items.compactMap(\.submenu?.title) == [
        "AstroStack", "File", "Edit", "View", "Window",
      ])
  }
}
