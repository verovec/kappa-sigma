package import AppKit

/// The one folder picker: folders only, opened on `folder` (Settings' pickers, File › Open Run…).
package enum FolderPanel {
  /// A panel over `folder` (the user's last folder when `nil`); `canCreate` offers New Folder.
  package static func make(startingIn folder: URL?, canCreate: Bool) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = canCreate
    panel.directoryURL = folder
    return panel
  }

  /// Runs `panel` and returns the folder picked, `nil` when cancelled.
  package static func pick(_ panel: NSOpenPanel) -> URL? {
    panel.runModal() == .OK ? panel.url : nil
  }
}
