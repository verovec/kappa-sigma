package import AppKit

/// Opens an untitled project when the app starts without a document, as document apps do;
/// `NSDocumentController` does the rest.
package final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Yes: a launch without a file opens an untitled project.
  package func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    Self.launchImage == nil
  }

  /// `-openImage <path>` on the command line opens that FITS in the viewer at launch.
  package func applicationDidFinishLaunching(_ notification: Notification) {
    if let path = Self.launchImage { ImageViewerWindow.show(URL(fileURLWithPath: path)) }
  }

  /// File › Open Image…: a FITS in the viewer.
  @objc package func openImage(_ sender: Any?) {
    ImageViewerWindow.choose()
  }

  private static var launchImage: String? { UserDefaults.standard.string(forKey: "openImage") }

  /// AppKit does not close documents on quit; closing them checkpoints each `project.db` and
  /// deletes the temporary package of an untitled project the user chose not to save.
  package func applicationWillTerminate(_ notification: Notification) {
    for document in NSDocumentController.shared.documents {
      document.close()
    }
  }
}
