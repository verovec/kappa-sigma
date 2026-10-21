package import Foundation

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
