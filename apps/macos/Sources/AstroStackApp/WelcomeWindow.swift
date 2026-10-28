package import AppKit
internal import OSLog
package import ProjectKit
package import StackKit
internal import SwiftUI

/// The welcome window: one window, reused, that closes once a project opens.
///
/// Shown at launch when no project is restored, from the Dock with no window open, and from
/// Window › Welcome Window and File › New Project.
package enum WelcomeWindow {
  private static var window: NSWindow?
  /// The live host-tool client.
  package static let hostTools = HostTools.live()
  /// The recent projects, most recent first: AppKit's recents, the one source (welcome window,
  /// File › Open Recent, the retention review).
  package static func recentURLs() -> [URL] {
    NSDocumentController.shared.recentDocumentURLs
  }

  /// Every project on disk and the tool statuses, shared with Settings › Tools.
  package static let model = WelcomeModel(
    recentURLs: recentURLs, tools: hostTools, openProjects: openProjects,
    folderURLs: { ProjectCatalog.folderListing(of: NewProject.projectsFolder) })

  /// The retention policy's launch review over the recent projects no window has open (0114).
  package static let retention = RetentionReview(
    setting: RetentionSetting(),
    recentURLs: recentURLs, openProjects: openProjectKeys)

  /// Runs the launch review (the welcome window is up: no document is open).
  package static func reviewRetention() async {
    await retention.scan()
  }

  /// Shows the window with the recent projects re-read and the tools re-checked.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    Task { await model.reload() }
    // Tools are probed once; afterwards only « Re-check » runs siril-cli again.
    if model.tools.isEmpty { Task { await model.recheckTools() } }
    window.makeKeyAndOrderFront(nil)
    return window
  }

  /// Shows the window with the « New Project… » sheet up.
  @discardableResult
  package static func showNewProject() -> NSWindow {
    let window = show()
    model.isNaming = true
    return window
  }

  /// Closes the window if it is up: a project window just opened.
  package static func dismiss() {
    model.isNaming = false
    // The sheet's list would be stale by the next time the window shows: asked again next launch.
    retention.postpone()
    window?.close()
  }

  /// Whether the window is on screen.
  package static var isVisible: Bool { window?.isVisible ?? false }

  private static func make() -> NSWindow {
    let actions = WelcomeView.Actions(
      open: { url in Task { await open(url) } }, choose: choose,
      create: { try NewProject.create(target: $0) })
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: WelcomeView(model: model, actions: actions, retention: retention)
          .interfaceLocale()))
    window.title = String(localized: .app("Welcome to AstroStack"))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  /// The key (`WelcomeModel.key`) of every project open in a document; reads no database.
  package static func openProjectKeys() -> Set<String> {
    Set(
      NSDocumentController.shared.documents.compactMap {
        guard let document = $0 as? ProjectDocument else { return nil }
        // The file URL is there before the package finishes opening.
        return (document.packageURL ?? document.fileURL).map(WelcomeModel.key)
      })
  }

  /// Every project open in a document, in the documents' order, with that document's counts.
  package static func openProjects() -> [(URL, ProjectSummary?)] {
    NSDocumentController.shared.documents.compactMap { document in
      // The file URL is there before the package finishes opening (as in `openProjectKeys`).
      guard let document = document as? ProjectDocument,
        let url = document.packageURL ?? document.fileURL
      else { return nil }
      return (url, document.projectSummary())
    }
  }

  /// Open…: the projects picked in the Open panel, opened like a recent one.
  private static func choose() {
    let urls = NSDocumentController.shared.urlsFromRunningOpenPanel() ?? []
    Task { for url in urls { await open(url) } }
  }

  /// Opens the project at `url` and dismisses this window; a failure goes to `report`, never
  /// swallowed.
  package static func open(
    _ url: URL, report: (any Error) -> Void = { NSAlert(error: $0).runModal() }
  ) async {
    do {
      _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
      // An already open project only comes forward: its window was made long ago.
      dismiss()
    } catch {
      logger.error("cannot open \(url.path, privacy: .public): \(error, privacy: .public)")
      report(error)
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/welcome")
}
