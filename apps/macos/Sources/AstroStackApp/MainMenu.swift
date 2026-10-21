package import AppKit

/// Builds the application's main menu, its titles from the app's catalog.
///
/// Every action travels the responder chain (`target` nil), so the key window's
/// `ProjectDocument` or the shared `NSDocumentController` answers it.
package enum MainMenu {
  private typealias Entry = (title: LocalizedStringResource, action: Selector?, key: String)

  /// Identifies the Window menu's item in the bar: AppKit needs that menu (`windowsMenu`), and
  /// its title changes with the language.
  package static let windowMenuID = NSUserInterfaceItemIdentifier("fr.astrostack.menu.window")

  /// The main menu bar: application, File, Edit, View, Window; `locale` pins the language
  /// (tests), the user's languages otherwise.
  package static func make(locale: Locale? = nil) -> NSMenu {
    let bar = NSMenu(title: "Main")
    let menus = [
      application(locale), file(locale), edit(locale), view(locale), window(locale),
    ]
    for menu in menus {
      let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      item.submenu = menu
      bar.addItem(item)
    }
    bar.items.last?.identifier = windowMenuID
    return bar
  }

  /// The Window menu of `bar`, found by identity whatever the language.
  package static func windowsMenu(in bar: NSMenu) -> NSMenu? {
    bar.items.first { $0.identifier == windowMenuID }?.submenu
  }

  // MARK: - Menus

  private static func application(_ locale: Locale?) -> NSMenu {
    let menu = submenu(
      "AstroStack",
      [
        (
          .app("About AstroStack", locale: locale),
          #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""
        ),
        nil,
        (.app("Settings…", locale: locale), #selector(AppDelegate.showSettings(_:)), ","),
        nil,
        (.app("Hide AstroStack", locale: locale), #selector(NSApplication.hide(_:)), "h"),
        (
          .app("Show All", locale: locale),
          #selector(NSApplication.unhideAllApplications(_:)), ""
        ),
        nil,
        (.app("Quit AstroStack", locale: locale), #selector(NSApplication.terminate(_:)), "q"),
      ])
    let hideOthers = NSMenuItem(
      title: String(localized: .app("Hide Others", locale: locale)),
      action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    menu.insertItem(hideOthers, at: 5)
    return menu
  }

  private static func file(_ locale: Locale?) -> NSMenu {
    let menu = submenu(
      String(localized: .app("File", locale: locale)),
      [
        (.app("New Project", locale: locale), #selector(NSDocumentController.newDocument(_:)), "n"),
        (.app("Open…", locale: locale), #selector(NSDocumentController.openDocument(_:)), "o"),
        (.app("Open Image…", locale: locale), #selector(AppDelegate.openImage(_:)), "O"),
        (.app("Open Run…", locale: locale), #selector(AppDelegate.openRun(_:)), "r"),
        nil,
        (.app("Close", locale: locale), #selector(NSWindow.performClose(_:)), "w"),
        (.app("Save", locale: locale), #selector(NSDocument.save(_:)), "s"),
        (.app("Save As…", locale: locale), #selector(NSDocument.saveAs(_:)), "s"),
      ])
    menu.items.last?.keyEquivalentModifierMask = [.command, .shift]
    return menu
  }

  private static func edit(_ locale: Locale?) -> NSMenu {
    submenu(
      String(localized: .app("Edit", locale: locale)),
      [
        (.app("Undo", locale: locale), Selector(("undo:")), "z"),
        (.app("Redo", locale: locale), Selector(("redo:")), "Z"),
        nil,
        (.app("Cut", locale: locale), #selector(NSText.cut(_:)), "x"),
        (.app("Copy", locale: locale), #selector(NSText.copy(_:)), "c"),
        (.app("Paste", locale: locale), #selector(NSText.paste(_:)), "v"),
        (.app("Select All", locale: locale), #selector(NSText.selectAll(_:)), "a"),
      ])
  }

  private static func view(_ locale: Locale?) -> NSMenu {
    submenu(
      String(localized: .app("View", locale: locale)),
      [
        (.app("Zoom to Fit", locale: locale), Selector(("zoomToFit:")), "0"),
        (.app("Actual Pixels", locale: locale), Selector(("zoomToActualSize:")), "1"),
      ])
  }

  private static func window(_ locale: Locale?) -> NSMenu {
    let menu = submenu(
      String(localized: .app("Window", locale: locale)),
      [
        (.app("Minimize", locale: locale), #selector(NSWindow.performMiniaturize(_:)), "m"),
        (.app("Zoom", locale: locale), #selector(NSWindow.performZoom(_:)), ""),
        nil,
        (.app("Welcome Window", locale: locale), #selector(AppDelegate.showWelcome(_:)), ""),
        nil,
        (
          .app("Bring All to Front", locale: locale),
          #selector(NSApplication.arrangeInFront(_:)), ""
        ),
      ])
    #if DEBUG
      menu.addItem(.separator())
      menu.addItem(
        NSMenuItem(
          title: String(localized: .app("Component Gallery", locale: locale)),
          action: #selector(AppDelegate.showComponentGallery(_:)), keyEquivalent: ""))
    #endif
    return menu
  }

  /// A menu of `entries`, where `nil` is a separator.
  private static func submenu(_ title: String, _ entries: [Entry?]) -> NSMenu {
    let menu = NSMenu(title: title)
    for entry in entries {
      guard let entry else {
        menu.addItem(.separator())
        continue
      }
      menu.addItem(
        NSMenuItem(
          title: String(localized: entry.title), action: entry.action, keyEquivalent: entry.key))
    }
    return menu
  }
}
