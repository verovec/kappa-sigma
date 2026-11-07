internal import RenderKit
package import SwiftUI

/// « S3 connections… » beside a line that says a connection is needed, or « Settings… » in the
/// welcome window (card 0177): Settings was reachable from the menu bar only.
package struct OpenSettingsButton: View {
  /// Opens Settings on a tab (`nil`: the one shown last).
  package typealias Open = @MainActor (SettingsTab?) -> Void

  /// The tab to open on, `nil` for the one shown last.
  package let tab: SettingsTab?
  /// Opens the window: `SettingsWindow.show(tab:)` in the app, a recorder in tests.
  package let open: Open

  /// A button opening Settings on `tab` through `open`.
  package init(
    tab: SettingsTab?, open: @escaping Open = Self.window
  ) {
    self.tab = tab
    self.open = open
  }

  /// The app's Settings window on `tab`.
  package static func window(_ tab: SettingsTab?) {
    SettingsWindow.show(tab: tab)
  }

  /// What a click does.
  package func press() { open(tab) }

  /// The button's title: the connections when it opens on them, Settings otherwise.
  package var title: LocalizedStringResource {
    tab == .s3 ? .app("S3 connections…") : .app("Settings…")
  }

  package var body: some View {
    Button(action: press) { Text(title) }
      .accessible(.openSettings(tab?.rawValue ?? "last"), label: title)
  }
}
