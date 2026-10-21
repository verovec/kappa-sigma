package import AppKit
internal import OSLog
internal import ProjectKit
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
  /// The recent projects and tool statuses, shared with Settings › Tools.
  package static let model = WelcomeModel(
    recentURLs: { NSDocumentController.shared.recentDocumentURLs }, tools: hostTools,
    openProjects: openProjects)

  /// Shows the window with the recent projects re-read and the tools re-checked.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    Task {
      await model.reload()
      await model.recheckTools()
    }
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
    window?.close()
  }

  /// Whether the window is on screen.
  package static var isVisible: Bool { window?.isVisible ?? false }

  private static func make() -> NSWindow {
    let actions = WelcomeView.Actions(
      open: open, choose: choose, create: { try NewProject.create(target: $0) })
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: WelcomeView(model: model, actions: actions).interfaceLocale()))
    window.title = String(localized: .app("Welcome to AstroStack"))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  /// The counts of every project open in a document, keyed like `WelcomeModel` looks them up.
  private static func openProjects() -> [URL: ProjectSummary?] {
    var open: [URL: ProjectSummary?] = [:]
    for case let document as ProjectDocument in NSDocumentController.shared.documents {
      guard let url = document.packageURL else { continue }
      open[url.standardizedFileURL] = document.projectSummary()
    }
    return open
  }

  /// Open…: the projects picked in the Open panel, opened like a recent one.
  private static func choose() {
    for url in NSDocumentController.shared.urlsFromRunningOpenPanel() ?? [] { open(url) }
  }

  /// Opens the project at `url` (its window dismisses this one); a failure is shown, not swallowed.
  private static func open(_ url: URL) {
    Task {
      do {
        _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
      } catch {
        logger.error("cannot open \(url.path, privacy: .public): \(error, privacy: .public)")
        NSAlert(error: error).runModal()
      }
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/welcome")
}
