package import AppKit

/// Builds the application's main menu.
///
/// Every action travels the responder chain (`target` nil), so the key window's
/// `ProjectDocument` or the shared `NSDocumentController` answers it.
package enum MainMenu {
  private typealias Entry = (title: String, action: Selector?, key: String)

  /// The main menu bar: application, File, Edit, Window.
  package static func make() -> NSMenu {
    let bar = NSMenu(title: "Main")
    for menu in [application(), file(), edit(), window()] {
      let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      item.submenu = menu
      bar.addItem(item)
    }
    return bar
  }

  // MARK: - Menus

  private static func application() -> NSMenu {
    let menu = submenu(
      "AstroStack",
      [
        ("About AstroStack", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
        nil,
        ("Hide AstroStack", #selector(NSApplication.hide(_:)), "h"),
        ("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
        nil,
        ("Quit AstroStack", #selector(NSApplication.terminate(_:)), "q"),
      ])
    let hideOthers = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    menu.insertItem(hideOthers, at: 3)
    return menu
  }

  private static func file() -> NSMenu {
    let menu = submenu(
      "File",
      [
        ("New Project", #selector(NSDocumentController.newDocument(_:)), "n"),
        ("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
        nil,
        ("Close", #selector(NSWindow.performClose(_:)), "w"),
        ("Save", #selector(NSDocument.save(_:)), "s"),
        ("Save As…", #selector(NSDocument.saveAs(_:)), "s"),
      ])
    menu.items.last?.keyEquivalentModifierMask = [.command, .shift]
    return menu
  }

  private static func edit() -> NSMenu {
    submenu(
      "Edit",
      [
        ("Undo", Selector(("undo:")), "z"),
        ("Redo", Selector(("redo:")), "Z"),
        nil,
        ("Cut", #selector(NSText.cut(_:)), "x"),
        ("Copy", #selector(NSText.copy(_:)), "c"),
        ("Paste", #selector(NSText.paste(_:)), "v"),
        ("Select All", #selector(NSText.selectAll(_:)), "a"),
      ])
  }

  private static func window() -> NSMenu {
    submenu(
      "Window",
      [
        ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ("Zoom", #selector(NSWindow.performZoom(_:)), ""),
        nil,
        ("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
      ])
  }

  /// A menu of `entries`, where `nil` is a separator.
  private static func submenu(_ title: String, _ entries: [Entry?]) -> NSMenu {
    let menu = NSMenu(title: title)
    for entry in entries {
      guard let entry else {
        menu.addItem(.separator())
        continue
      }
      menu.addItem(NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.key))
    }
    return menu
  }
}
