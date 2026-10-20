package import AppKit
internal import OSLog
internal import SwiftUI

/// AstroStack › Settings… (⌘,): one window, reused.
package enum SettingsWindow {
  private static var window: NSWindow?

  /// Shows the Settings window, creating it the first time.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private static func make() -> NSWindow {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: SettingsView(setting: LanguageSetting(), relaunch: relaunch)))
    window.title = String(localized: .app("Settings"))
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    return window
  }

  /// Opens a new instance of the app, then quits this one (the language is read at launch).
  ///
  /// The projects are closed first, so the new instance never opens a `project.db` this one is
  /// still checkpointing; with unsaved changes nothing relaunches and the user is told why.
  private static func relaunch() {
    let documents = NSDocumentController.shared
    guard !documents.hasEditedDocuments else {
      let alert = NSAlert()
      alert.messageText = String(localized: .app("Save your projects before relaunching."))
      alert.runModal()
      return
    }
    for document in documents.documents { document.close() }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    Task {
      do {
        _ = try await NSWorkspace.shared.openApplication(
          at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
      } catch {
        logger.error("relaunch failed: \(error, privacy: .public)")
      }
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/settings")
}
