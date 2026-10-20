package import AppKit

/// Opens an untitled project when the app starts without a document, as document apps do;
/// `NSDocumentController` does the rest.
package final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Yes: a launch without a file opens an untitled project.
  package func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

  /// AppKit does not close documents on quit; closing them checkpoints each `project.db` and
  /// deletes the temporary package of an untitled project the user chose not to save.
  package func applicationWillTerminate(_ notification: Notification) {
    for document in NSDocumentController.shared.documents {
      document.close()
    }
  }
}
