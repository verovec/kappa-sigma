package import AppKit

/// Builds the application's main menu from `CommandCatalog` (card 0079), titles from the app's
/// catalog.
///
/// Every action travels the responder chain (`target` nil), so the key window's
/// `ProjectDocument` or the shared `NSDocumentController` answers it. A command without an
/// action (a feature not landed yet) is shown disabled.
package enum MainMenu {
  /// Identifies the Window menu's item in the bar: AppKit needs that menu (`windowsMenu`), and
  /// its title changes with the language.
  package static let windowMenuID = NSUserInterfaceItemIdentifier("fr.astrostack.menu.window")
  /// Identifies the Help menu's item in the bar (`helpMenu`), whatever the language.
  package static let helpMenuID = NSUserInterfaceItemIdentifier("fr.astrostack.menu.help")

  /// The main menu bar, one menu per `CommandMenu`; `locale` pins the language (tests), the
  /// user's languages otherwise.
  package static func make(locale: Locale? = nil) -> NSMenu {
    let bar = NSMenu(title: "Main")
    for kind in CommandMenu.allCases {
      let menu = submenu(kind, locale: locale)
      let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      item.submenu = menu
      item.identifier =
        switch kind {
        case .window: windowMenuID
        case .help: helpMenuID
        default: nil
        }
      bar.addItem(item)
    }
    return bar
  }

  /// The Window menu of `bar`, found by identity whatever the language.
  package static func windowsMenu(in bar: NSMenu) -> NSMenu? {
    bar.items.first { $0.identifier == windowMenuID }?.submenu
  }

  /// The Help menu of `bar`, found by identity whatever the language.
  package static func helpMenu(in bar: NSMenu) -> NSMenu? {
    bar.items.first { $0.identifier == helpMenuID }?.submenu
  }

  /// The menu `kind`: its catalog commands in order, separators where declared.
  private static func submenu(_ kind: CommandMenu, locale: Locale?) -> NSMenu {
    let menu = NSMenu(title: kind.title(locale: locale))
    menu.autoenablesItems = true
    for command in CommandCatalog.commands(in: kind) where isBuilt(command) {
      if command.separatorBefore, !menu.items.isEmpty { menu.addItem(.separator()) }
      menu.addItem(item(command, locale: locale))
    }
    return menu
  }

  /// The menu item of `command`, its key equivalent as AppKit expects it.
  static func item(_ command: AppCommand, locale: Locale?) -> NSMenuItem {
    let item = NSMenuItem(
      title: String(localized: command.title(locale: locale)),
      action: command.action.map(NSSelectorFromString),
      keyEquivalent: command.keyEquivalent)
    item.identifier = NSUserInterfaceItemIdentifier("fr.astrostack.command." + command.id)
    if !command.keyEquivalent.isEmpty {
      item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: command.keyModifiers)
    }
    return item
  }

  /// Debug-only commands exist in debug builds only.
  private static func isBuilt(_ command: AppCommand) -> Bool {
    #if DEBUG
      true
    #else
      !command.debugOnly
    #endif
  }
}
