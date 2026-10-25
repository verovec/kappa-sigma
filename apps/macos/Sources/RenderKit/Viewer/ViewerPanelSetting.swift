package import Foundation

/// Whether the viewer's « View » panel is shown (card 0126): the user's last choice, read by every
/// new `ViewerModel` (Studio, viewer window, layer detail) so they all open the same way.
///
/// Display state only (R2): hiding the panel hides controls, never a value.
package nonisolated struct ViewerPanelSetting {
  private static let key = "viewer.showsPanel"
  private let defaults: UserDefaults

  /// The setting stored in `defaults` (a scratch suite in tests).
  package init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The panel is shown; true until the user hides it.
  package var showsPanel: Bool {
    get { defaults.object(forKey: Self.key) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: Self.key) }
  }
}
