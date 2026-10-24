package import AppKit
package import StackKit

/// Shows the welcome window when the app starts without a document (or is reopened from the Dock
/// with no window): a project is named after its target there, never « Untitled ».
/// `NSDocumentController` does the rest.
package final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Set once AppKit first asked: `-openImage` only holds the welcome window back at launch,
  /// whenever AppKit asks then (restoration may defer it past `applicationDidFinishLaunching`).
  private var askedOnce = false
  /// Armed by a real launch only (a test never runs `applicationDidFinishLaunching`): the
  /// retention review runs once, the first time the app has no document to show (card 0114).
  private var retentionArmed = false

  /// Yes, unless the app is launching with `-openImage`: AppKit then asks
  /// `applicationOpenUntitledFile` (at launch, and from the Dock with no window open).
  package func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    defer { askedOnce = true }
    return askedOnce || Self.launchImage == nil
  }

  /// Shows the welcome window instead of creating an untitled project.
  ///
  /// AppKit calls it once restoration is over and no document opened: the first time after a
  /// launch, stacks never exported are reviewed — never while a project is restoring or opening.
  package func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
    WelcomeWindow.show()
    if retentionArmed {
      retentionArmed = false
      Task { await WelcomeWindow.reviewRetention() }
    }
    return true
  }

  /// `-openImage <path>` opens that FITS in the viewer at launch; `-openRun <folder>` opens a
  /// legacy run into the open project, or an untitled one so the run is still recorded.
  package func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await Self.openLaunchArguments(UserDefaults.standard) }
    Task { await Self.sweepLeftovers() }
    retentionArmed = true
  }

  /// What a killed run left (its Siril, its tens of GB of work files, an untitled project) goes
  /// at launch, off the main actor; a folder whose owner still runs is never touched (0113).
  @concurrent
  package nonisolated static func sweepLeftovers(roots: [LeftoverSweep.Root]? = nil) async {
    LeftoverSweep(roots: roots ?? leftoverRoots(work: RunServices.live.scratch)).run()
  }

  /// The app's scratch roots with the runs' work folder `work` (Settings, card 0098); the default
  /// one too when another was chosen, where the runs before the choice worked.
  package nonisolated static func leftoverRoots(
    work: URL, defaultWork: URL = ScratchSetting.defaultFolder
  ) -> [LeftoverSweep.Root] {
    var roots = LeftoverSweep.appRoots(work: work)
    if work.standardizedFileURL != defaultWork.standardizedFileURL {
      roots.append(LeftoverSweep.Root(folder: defaultWork, prefix: "run_"))
    }
    return roots
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
      // A developer flag: with no project open, an untitled one records the run.
      let project =
        LegacyRunWindow.projectDocument()
        ?? (try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true))
        as? ProjectDocument
      let window = await LegacyRunWindow.open(
        URL(fileURLWithPath: path), into: project, report: report)
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

  /// File › New Project…: the welcome window's sheet naming the project after its target.
  @objc package func newProject(_ sender: Any?) {
    WelcomeWindow.showNewProject()
  }

  /// Window › Welcome Window: recent projects, a new project, the host tools.
  @objc package func showWelcome(_ sender: Any?) {
    WelcomeWindow.show()
  }

  /// AstroStack › Settings…: the interface language and the host tools.
  @objc package func showSettings(_ sender: Any?) {
    SettingsWindow.show()
  }

  /// Help › Keyboard Shortcuts: every command of the catalog and its shortcut.
  @objc package func showShortcuts(_ sender: Any?) {
    UtilityWindow.show("shortcuts", title: .app("Keyboard Shortcuts")) { ShortcutsSheet() }
  }

  /// Help › Glossary: the terms the app uses, with their definitions.
  @objc package func showGlossary(_ sender: Any?) {
    UtilityWindow.show("glossary", title: .app("Glossary")) { GlossaryView() }
  }

  /// Window › Component Gallery (debug builds): the design system's components.
  @objc package func showComponentGallery(_ sender: Any?) {
    ComponentGalleryWindow.show()
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
