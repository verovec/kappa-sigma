import AppKit
import AstroStackApp
import RenderKit
import Testing

@MainActor
@Suite("MainMenu: the document commands reach AppKit's document machinery, in fr and en")
struct MainMenuTests {
  struct Item: Sendable, CustomTestStringConvertible {
    let menu: String
    let title: String
    /// The menu and title in French.
    let french: (menu: String, title: String)
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: String
    var testDescription: String { "\(menu) › \(title)" }
  }

  nonisolated static let items: [Item] = [
    Item(
      menu: "File", title: "New Project…", french: ("Fichier", "Nouveau projet…"), key: "n",
      modifiers: .command, action: "newProject:"),
    Item(
      menu: "File", title: "Open…", french: ("Fichier", "Ouvrir…"), key: "o", modifiers: .command,
      action: "openDocument:"),
    Item(
      menu: "File", title: "Close", french: ("Fichier", "Fermer"), key: "w", modifiers: .command,
      action: "performClose:"),
    Item(
      menu: "File", title: "Open Run…", french: ("Fichier", "Ouvrir un run…"), key: "r",
      modifiers: .command, action: "openRun:"),
    Item(
      menu: "File", title: "Save", french: ("Fichier", "Enregistrer"), key: "s",
      modifiers: .command, action: "saveDocument:"),
    Item(
      menu: "File", title: "Save As…", french: ("Fichier", "Enregistrer sous…"), key: "s",
      modifiers: [.command, .shift], action: "saveDocumentAs:"),
    Item(
      menu: "AstroStack", title: "Quit AstroStack", french: ("AstroStack", "Quitter AstroStack"),
      key: "q", modifiers: .command, action: "terminate:"),
    Item(
      menu: "AstroStack", title: "Settings…", french: ("AstroStack", "Réglages…"), key: ",",
      modifiers: .command, action: "showSettings:"),
    Item(
      menu: "AstroStack", title: "Hide Others", french: ("AstroStack", "Masquer les autres"),
      key: "h", modifiers: [.command, .option], action: "hideOtherApplications:"),
    Item(
      menu: "File", title: "Open Image…", french: ("Fichier", "Ouvrir une image…"), key: "O",
      modifiers: .command, action: "openImage:"),
    Item(
      menu: "View", title: "Zoom to Fit", french: ("Présentation", "Ajuster à la fenêtre"),
      key: "0", modifiers: .command, action: "zoomToFit:"),
    Item(
      menu: "View", title: "Actual Pixels", french: ("Présentation", "Taille réelle"), key: "1",
      modifiers: .command, action: "zoomToActualSize:"),
    Item(
      menu: "Edit", title: "Undo", french: ("Édition", "Annuler"), key: "z", modifiers: .command,
      action: "undo:"),
    Item(
      menu: "Window", title: "Minimize", french: ("Fenêtre", "Placer dans le Dock"), key: "m",
      modifiers: .command, action: "performMiniaturize:"),
  ]

  static let english = Locale(identifier: "en")
  static let french = Locale(identifier: "fr")

  @Test("each command has its title in both languages, its shortcut and action", arguments: items)
  func testMainMenu_item(_ expected: Item) throws {
    for (locale, menuTitle, title) in [
      (Self.english, expected.menu, expected.title),
      (Self.french, expected.french.menu, expected.french.title),
    ] {
      let menu = try #require(
        MainMenu.make(locale: locale).items.first { $0.submenu?.title == menuTitle }?.submenu)
      let item = try #require(menu.items.first { $0.title == title })
      #expect(item.keyEquivalent == expected.key)
      #expect(item.keyEquivalentModifierMask == expected.modifiers)
      #expect(item.action.map(NSStringFromSelector) == expected.action)
    }
  }

  @Test("menus appear in the standard order, titled in the language")
  func testMainMenu_order() {
    #expect(
      MainMenu.make(locale: Self.english).items.compactMap(\.submenu?.title) == [
        "AstroStack", "File", "Edit", "View", "Window", "Help",
      ])
    #expect(
      MainMenu.make(locale: Self.french).items.compactMap(\.submenu?.title) == [
        "AstroStack", "Fichier", "Édition", "Présentation", "Fenêtre", "Aide",
      ])
  }

  @Test("every menu item is a catalog command, in catalog order, with its declared shortcut")
  func testMenusGeneratedFromCatalog() {
    let bar = MainMenu.make(locale: Self.french)
    for (kind, item) in zip(CommandMenu.allCases, bar.items) {
      let items = item.submenu?.items.filter { !$0.isSeparatorItem } ?? []
      // A submenu's own commands sit inside it (card 0144), never at the menu's top level.
      let commands = CommandCatalog.commands(in: kind).filter { $0.isBuilt && $0.parent == nil }
      #expect(
        items.compactMap { $0.identifier?.rawValue }
          == commands.map { "fr.astrostack.command." + $0.id }, "\(kind)")
      for (menuItem, command) in zip(items, commands) {
        #expect(menuItem.keyEquivalent == command.keyEquivalent, "\(command.id)")
        // A catalog submenu holds only its catalog commands until it opens and fills itself
        // (AppKit gives its item `submenuAction:`).
        guard let submenu = command.submenu else {
          #expect(menuItem.action.map(NSStringFromSelector) == command.action, "\(command.id)")
          continue
        }
        #expect(
          menuItem.submenu?.items.filter { !$0.isSeparatorItem }.compactMap(\.identifier?.rawValue)
            == CommandCatalog.commands(in: submenu).map { "fr.astrostack.command." + $0.id })
      }
    }
  }

  /// The classes that can answer a menu action through the responder chain.
  static let responders: [AnyClass] = [
    NSApplication.self, AppDelegate.self, NSDocumentController.self, ProjectDocument.self,
    NSWindow.self, NSTextView.self, ViewerMTKView.self,
  ]

  @Test("every catalog action is implemented by a class of the responder chain (no typo ships)")
  func testEveryActionHasAResponder() {
    for command in CommandCatalog.commands {
      guard let action = command.action else { continue }
      let selector = NSSelectorFromString(action)
      #expect(
        Self.responders.contains { $0.instancesRespond(to: selector) },
        "\(command.id): nothing answers \(action)")
    }
  }

  @Test("Help holds the shortcuts, the glossary and the first-stack guide")
  func testHelpMenu() throws {
    let help = try #require(MainMenu.helpMenu(in: MainMenu.make(locale: Self.french)))
    #expect(help.title == "Aide")
    let titles = help.items.filter { !$0.isSeparatorItem }.map(\.title)
    #expect(titles == ["Raccourcis clavier", "Glossaire", "Guide du premier empilement"])
    #expect(help.items.last?.action.map(NSStringFromSelector) == "showGuide:")
    #expect(help.items.first?.action.map(NSStringFromSelector) == "showShortcuts:")
  }

  @Test("the Window menu is found by identity, whatever its title")
  func testWindowMenuFoundWithoutTitle() throws {
    let bar = MainMenu.make(locale: Self.french)
    let window = try #require(MainMenu.windowsMenu(in: bar))
    #expect(window.title == "Fenêtre")
    #expect(window.items.contains { $0.title == "Placer dans le Dock" })
    #expect(bar.item(withTitle: "Window") == nil, "no English title to find it by")
  }
}
