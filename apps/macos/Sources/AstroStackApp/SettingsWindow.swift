package import AppKit
internal import OSLog
internal import SwiftUI

/// AstroStack › Settings… (⌘,): one window, reused.
package enum SettingsWindow {
  /// Shows the Settings window, creating it the first time.
  @discardableResult
  package static func show() -> NSWindow {
    // The tools are probed once; afterwards only « Re-check » runs siril-cli again.
    if WelcomeWindow.model.tools.isEmpty { Task { await WelcomeWindow.model.recheckTools() } }
    return UtilityWindow.show("settings", title: .app("Settings"), resizable: false) {
      SettingsView(setting: LanguageSetting(), relaunch: relaunch, tools: WelcomeWindow.model)
    }
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
    ProjectDocument.closeQuietly(documents.documents)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    Task {
      do {
        _ = try await NSWorkspace.shared.openApplication(
          at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
      } catch {
        logger.error("relaunch failed: \(error, privacy: .public)")
        // The projects are closed: never leave the app without a window.
        WelcomeWindow.show()
      }
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/settings")
}
