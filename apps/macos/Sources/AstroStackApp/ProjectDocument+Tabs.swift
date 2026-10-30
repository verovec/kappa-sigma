internal import AppKit

extension ProjectDocument {
  /// The tab group of project windows: viewers and legacy runs keep their own windows.
  package static let tabbingIdentifier = "fr.astrostack.project"

  /// The tab bar's « + » (and Window › New Tab): New Project…, the welcome window's naming sheet,
  /// never the untitled document `NSDocumentController` would open further down the chain.
  @objc package func newWindowForTab(_ sender: Any?) {
    WelcomeWindow.showNewProject()
  }
}
