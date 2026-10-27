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
  /// user's languages otherwise; `recentProjects` fills File › Open Recent (a menu keeps its
  /// delegate weakly: the caller owns it).
  package static func make(
    locale: Locale? = nil, recentProjects: RecentProjectsMenu = .live
  ) -> NSMenu {
    let bar = NSMenu(title: "Main")
    for kind in CommandMenu.allCases {
      let menu = submenu(kind, locale: locale, recentProjects: recentProjects)
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

  /// The menu `kind`: its catalog commands in order, separators where declared, a command that
  /// opens a submenu with it.
  private static func submenu(
    _ kind: CommandMenu, locale: Locale?, recentProjects: RecentProjectsMenu
  ) -> NSMenu {
    let menu = NSMenu(title: kind.title(locale: locale))
    menu.autoenablesItems = true
    for command in CommandCatalog.commands(in: kind) where command.isBuilt && command.parent == nil
    {
      if command.separatorBefore, !menu.items.isEmpty { menu.addItem(.separator()) }
      let item = item(command, locale: locale)
      if let submenu = command.submenu {
        item.submenu = child(submenu, title: item.title, locale: locale, delegate: recentProjects)
      }
      menu.addItem(item)
    }
    return menu
  }

  /// The submenu `kind`: a separator, then its catalog commands; its delegate inserts the items
  /// it fills above the separator each time it opens.
  private static func child(
    _ kind: AppCommand.Submenu, title: String, locale: Locale?, delegate: RecentProjectsMenu
  ) -> NSMenu {
    let menu = NSMenu(title: title)
    menu.autoenablesItems = true
    menu.addItem(.separator())
    for command in CommandCatalog.commands(in: kind) where command.isBuilt {
      menu.addItem(item(command, locale: locale))
    }
    switch kind {
    case .recentProjects: menu.delegate = delegate
    }
    return menu
  }

  /// The menu item of `command`, its key equivalent as AppKit expects it.
  package static func item(_ command: AppCommand, locale: Locale?) -> NSMenuItem {
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
}
