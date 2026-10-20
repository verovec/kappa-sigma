package import AppKit

/// Opens an untitled project when the app starts without a document, as document apps do;
/// `NSDocumentController` does the rest.
package final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Yes: a launch without a file opens an untitled project.
  package func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    Self.launchImage == nil
  }

  /// `-openImage <path>` opens that FITS in the viewer at launch; `-openRun <folder>` opens a
  /// legacy run into the untitled project.
  package func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await Self.openLaunchArguments(UserDefaults.standard) }
  }

  /// Opens what `-openImage` / `-openRun` name in `defaults` (the command line's arguments).
  package static func openLaunchArguments(
    _ defaults: UserDefaults,
    report: @escaping @MainActor (any Error) -> Void = { NSAlert(error: $0).runModal() }
  ) async {
    if let path = defaults.string(forKey: "openImage") {
      await ImageViewerWindow.show(URL(fileURLWithPath: path), report: report).value
    }
    if let path = defaults.string(forKey: "openRun") {
      let window = await LegacyRunWindow.open(
        URL(fileURLWithPath: path), into: LegacyRunWindow.projectDocument(), report: report)
      if let window, let base = window.model.source.layers.first?.id {
        // A failed load shows in the window (`failure`); nothing is swallowed.
        try? await window.model.select(base)
      }
    }
  }

  /// File › Open Run…: a legacy run, read-only, its layers in a sidebar.
  @objc package func openRun(_ sender: Any?) {
    LegacyRunWindow.choose()
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
