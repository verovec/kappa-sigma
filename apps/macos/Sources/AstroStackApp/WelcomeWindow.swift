package import AppKit
internal import OSLog
package import StackKit
internal import SwiftUI

/// The welcome window: one window, reused, that closes once a project opens.
///
/// Shown at launch when no project is restored, from the Dock with no window open, and from
/// Window › Welcome Window.
package enum WelcomeWindow {
  private static var window: NSWindow?
  /// The live host-tool client, shared with Settings › Tools.
  package static let hostTools = HostTools.live()
  /// The recent projects and tool statuses, shared with Settings › Tools.
  package static let model = WelcomeModel(
    recentURLs: { NSDocumentController.shared.recentDocumentURLs }, tools: hostTools)

  /// Shows the window with the recent projects re-read and the tools re-checked.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    model.reload()
    Task { await model.recheckTools() }
    window.makeKeyAndOrderFront(nil)
    return window
  }

  /// Whether the window is on screen.
  package static var isVisible: Bool { window?.isVisible ?? false }

  private static func make() -> NSWindow {
    let actions = WelcomeView.Actions(
      open: open, choose: { NSDocumentController.shared.openDocument(nil) },
      create: { try NewProject.create(target: $0) })
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: WelcomeView(model: model, hostTools: hostTools, actions: actions)
          .interfaceLocale()))
    window.title = String(localized: .app("Welcome to AstroStack"))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  /// Opens the project at `url` and closes the welcome window; a failure is shown, not swallowed.
  private static func open(_ url: URL) {
    Task {
      do {
        _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        window?.close()
      } catch {
        logger.error("cannot open \(url.path, privacy: .public): \(error, privacy: .public)")
        NSAlert(error: error).runModal()
      }
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/welcome")
}
