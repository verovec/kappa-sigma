internal import Observation

/// The tab the Settings window shows (card 0177): kept by the window, so « S3 connections… » in
/// Import or Export can open it on its tab while ⌘, keeps the last one.
@Observable
package final class SettingsSelection {
  /// The tab shown.
  package var tab: SettingsTab

  /// A selection showing `tab`.
  package init(_ tab: SettingsTab = .general) { self.tab = tab }
}
