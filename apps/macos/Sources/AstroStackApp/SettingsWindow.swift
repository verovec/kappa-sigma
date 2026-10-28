package import AppKit
internal import OSLog
internal import StackKit
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

  /// The shell line that reopens the bundle (`$1`, never interpolated) once this process is gone.
  ///
  /// One instance is allowed (card 0147), so the relaunch waits for the quit from outside:
  /// `kill -0` only probes the pid, `open` without `-n` starts the one instance. The backgrounded
  /// subshell outlives this process and gives up after 15 s: a quit the user cancelled must not
  /// relaunch the app later. What `open` says lands in a log file, not nowhere.
  package static func relaunchScript(pid: Int32) -> String {
    "(for _ in $(seq 1 75); do kill -0 \(pid) 2>/dev/null || { open \"$1\"; exit 0; }; "
      + "sleep 0.2; done) >>\"${TMPDIR:-/tmp}/AstroStack-relaunch.log\" 2>&1 &"
  }

  /// Quits this instance and has the app reopened once it is gone (the language is read at
  /// launch).
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
    let script = relaunchScript(pid: getpid())
    let arguments = ["-c", script, "_", Bundle.main.bundlePath]
    Task {
      do {
        // The outer shell returns at once; its backgrounded subshell waits for our exit.
        _ = try await ToolProcess.runLines("/bin/sh", arguments: arguments) { _ in }
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
