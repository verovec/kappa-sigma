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

    /// As macOS writes it: ⌃⌥⇧⌘ then the key, uppercased (`⇧⌘O`, `⌥⌘H`, `⌘,`); the arrow,
    /// delete and return keys as their glyphs (`⌘←`, `⌘⌫`, `⌘↩`).
    package var symbols: String {
      let order: [(NSEvent.ModifierFlags, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
      ]
      return order.filter { flags.contains($0.0) }.map(\.1).joined()
        + (Self.glyphs[key] ?? key.uppercased())
    }

    /// The keys the sheet cannot print as typed.
    private static let glyphs: [String: String] = [
      "\u{F702}": "←", "\u{F703}": "→", "\u{F700}": "↑", "\u{F701}": "↓", "\u{8}": "⌫",
      "\u{7F}": "⌦", "\r": "↩", "\u{1B}": "⎋", "\t": "⇥",
    ]
  }

  /// A submenu the catalog declares by name, its items filled when it opens (card 0144): data,
  /// never a closure, so the catalog stays a list of values.
  package enum Submenu: Sendable {
    /// File › Open Recent: the recent projects, filled by `RecentProjectsMenu`.
    case recentProjects
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
  /// The submenu it opens instead of sending an action (File › Open Recent).
  package let submenu: Submenu?
  /// The submenu it sits in, after the items that submenu fills (« Clear Menu »); `nil` for an
  /// item of its menu.
  package let parent: Submenu?

  /// A command; `key` is an AppKit key equivalent (`"O"` means ⇧⌘O with `.command`).
  package init(
    _ id: String, _ titleKey: String.LocalizationValue, menu: CommandMenu?, action: String?,
    key: String = "", modifiers: NSEvent.ModifierFlags = .command, held: Bool = false,
    stage: JourneyStage? = nil, separatorBefore: Bool = false, debugOnly: Bool = false,
    submenu: Submenu? = nil, in parent: Submenu? = nil
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
    self.submenu = submenu
    self.parent = parent
  }

  /// Whether this build has the command: debug-only ones exist in debug builds only.
  package var isBuilt: Bool {
    #if DEBUG
      true
    #else
      !debugOnly
    #endif
  }

  /// Its title; `locale` pins the language (tests), the user's languages otherwise.
  package func title(locale: Locale? = nil) -> LocalizedStringResource {
    .app(titleKey, locale: locale)
  }
}
