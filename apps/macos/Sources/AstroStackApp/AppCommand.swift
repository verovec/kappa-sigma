package import AppKit
package import Foundation

/// One command of the app (card 0079): its catalog title, shortcut, menu and journey stage.
///
/// `CommandCatalog` declares every command once; `MainMenu` and the shortcuts sheet are built
/// from it, so a shortcut shown is a shortcut bound.
nonisolated package struct AppCommand: Equatable, Sendable {
  /// A key equivalent: the key and its modifiers, or a key held down (the viewer's ⌥ compare).
  package struct Shortcut: Hashable, Sendable {
    /// The key, lowercased (`""` for a modifier held alone).
    package let key: String
    /// The modifiers, ⇧ included when the key equivalent was an uppercase letter.
    package let modifiers: NSEvent.ModifierFlags.RawValue
    /// Held while it acts, not pressed once.
    package let held: Bool

    /// The shortcut of AppKit key equivalent `key` with `modifiers`: an uppercase letter means ⇧.
    package init(key: String, modifiers: NSEvent.ModifierFlags, held: Bool = false) {
      let shifted = key != key.lowercased()
      self.key = key.lowercased()
      self.modifiers =
        (shifted ? modifiers.union(.shift) : modifiers)
        .intersection([.control, .option, .shift, .command]).rawValue
      self.held = held
    }

    /// The modifiers as flags.
    package var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// As macOS writes it: ⌃⌥⇧⌘ then the key, uppercased (`⇧⌘O`, `⌥⌘H`, `⌘,`).
    package var symbols: String {
      let order: [(NSEvent.ModifierFlags, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
      ]
      return order.filter { flags.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
  }

  /// Stable identifier (`file.save`), never shown.
  package let id: String
  /// The catalog key of its title.
  package let titleKey: String.LocalizationValue
  /// Its menu, `nil` for a gesture or a held key that lives in a view.
  package let menu: CommandMenu?
  /// The responder-chain selector it sends; `nil` for a command not available yet (disabled).
  package let action: String?
  /// Its key equivalent, if any (normalised: conflicts and the shortcuts sheet).
  package let shortcut: Shortcut?
  /// The key equivalent as declared, which the menu item takes (`"O"`, not `"o"` + ⇧).
  package let keyEquivalent: String
  /// The modifiers as declared, which the menu item takes.
  package let keyModifiers: NSEvent.ModifierFlags.RawValue
  /// The journey stage it belongs to, `nil` for an app-wide command.
  package let stage: JourneyStage?
  /// A separator precedes it in its menu.
  package let separatorBefore: Bool
  /// Only in debug builds (the component gallery).
  package let debugOnly: Bool

  /// A command; `key` is an AppKit key equivalent (`"O"` means ⇧⌘O with `.command`).
  package init(
    _ id: String, _ titleKey: String.LocalizationValue, menu: CommandMenu?, action: String?,
    key: String = "", modifiers: NSEvent.ModifierFlags = .command, held: Bool = false,
    stage: JourneyStage? = nil, separatorBefore: Bool = false, debugOnly: Bool = false
  ) {
    self.id = id
    self.titleKey = titleKey
    self.menu = menu
    self.action = action
    self.shortcut =
      key.isEmpty && !held ? nil : Shortcut(key: key, modifiers: modifiers, held: held)
    self.keyEquivalent = held ? "" : key
    self.keyModifiers = modifiers.rawValue
    self.stage = stage
    self.separatorBefore = separatorBefore
    self.debugOnly = debugOnly
  }

  /// Its title; `locale` pins the language (tests), the user's languages otherwise.
  package func title(locale: Locale? = nil) -> LocalizedStringResource {
    .app(titleKey, locale: locale)
  }
}

/// A menu of the menu bar, in bar order.
nonisolated package enum CommandMenu: String, CaseIterable, Sendable {
  /// The application menu, titled with the product name.
  case application
  /// File.
  case file
  /// Edit.
  case edit
  /// View.
  case view
  /// Window.
  case window
  /// Help.
  case help

  /// Its title in the bar.
  package func title(locale: Locale? = nil) -> String {
    switch self {
    case .application: "AstroStack"
    case .file: String(localized: .app("File", locale: locale))
    case .edit: String(localized: .app("Edit", locale: locale))
    case .view: String(localized: .app("View", locale: locale))
    case .window: String(localized: .app("Window", locale: locale))
    case .help: String(localized: .app("Help", locale: locale))
    }
  }
}
