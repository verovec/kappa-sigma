import AppKit
import AstroStackApp
import Foundation
import Testing

/// The command catalog (card 0079): one declaration per command — title, shortcut, menu, stage —
/// from which the menus and the shortcuts sheet are built.
@Suite("CommandCatalog — one shortcut per command, every title in fr and en")
struct CommandCatalogTests {
  @Test("no two commands share a shortcut (an uppercase key is ⇧ + the key)")
  func testNoShortcutConflict() {
    let shortcuts = CommandCatalog.commands.compactMap { $0.shortcut }
    let duplicates = Dictionary(grouping: shortcuts, by: { $0 }).filter { $0.value.count > 1 }
    #expect(duplicates.isEmpty, "\(duplicates.keys)")
    #expect(shortcuts.count >= 20, "the menus' shortcuts are all declared")
  }

  @Test("an uppercase key equivalent is the same shortcut as ⇧ + the lowercase key")
  func testShortcutNormalisesShift() {
    let open = AppCommand.Shortcut(key: "O", modifiers: .command)
    #expect(open == AppCommand.Shortcut(key: "o", modifiers: [.command, .shift]))
    #expect(open.symbols == "⇧⌘O")
    #expect(AppCommand.Shortcut(key: ",", modifiers: .command).symbols == "⌘,")
    #expect(AppCommand.Shortcut(key: "h", modifiers: [.command, .option]).symbols == "⌥⌘H")
  }

  @Test("every command has a French and an English title, and a unique id")
  func testEveryCommandHasFrEnTitle() {
    let commands = CommandCatalog.commands
    #expect(Set(commands.map(\.id)).count == commands.count)
    for command in commands {
      var english = command.title(locale: Locale(identifier: "en"))
      english.locale = Locale(identifier: "en")
      var french = command.title(locale: Locale(identifier: "fr"))
      french.locale = Locale(identifier: "fr")
      let (en, fr) = (String(localized: english), String(localized: french))
      #expect(!en.isEmpty && !fr.isEmpty, "\(command.id)")
      #expect(en != fr, "\(command.id): \(en) is not translated")
    }
  }

  @Test("menu commands have an action; a held key is a viewer gesture, never a menu item")
  func testMenuAndHeldCommands() {
    for command in CommandCatalog.commands {
      if command.menu != nil {
        #expect(command.action != nil, "\(command.id)")
      }
      if command.shortcut?.held == true { #expect(command.menu == nil, "\(command.id)") }
    }
    #expect(CommandCatalog.command("viewer.compare")?.shortcut?.symbols == "⌥")
    #expect(CommandCatalog.command("viewer.compare")?.stage == .studio)
  }
}
