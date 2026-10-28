package import AppKit
package import Foundation
import RenderKit
import SwiftUI
import os

/// File › Open Run…: a finished legacy run (`<astro folder>/runs/<Object>/<run_id>/`) opened
/// read-only, its layers in a sidebar and the selected one in the viewer.
package final class LegacyRunWindow: NSWindowController, NSWindowDelegate {
  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "App/legacy-run")
  private static var opened: [LegacyRunWindow] = []
  /// The window's run and its selection.
  package let model: LegacyRunModel

  /// The run windows currently open.
  package static var openWindows: [LegacyRunWindow] { opened }

  /// Asks for a run folder and opens it into the current project.
  static func choose() {
    let panel = runPanel()
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    Task { await open(folder, into: projectDocument()) { NSAlert(error: $0).runModal() } }
  }

  /// The project a run opened now belongs to: the frontmost project, or the only one open (a run
  /// or image window may be in front).
  package static func projectDocument() -> ProjectDocument? {
    let controller = NSDocumentController.shared
    if let current = controller.currentDocument as? ProjectDocument { return current }
    let projects = controller.documents.compactMap { $0 as? ProjectDocument }
    return projects.count == 1 ? projects.first : nil
  }

  /// The folder picker: folders only, starting in the astro folder's `runs` (Settings, 0148).
  package static func runPanel() -> NSOpenPanel {
    FolderPanel.make(startingIn: AstroFolderSetting().runs, canCreate: false)
  }

  /// Opens the run, handing a failure to `report` (an alert in the app): never swallowed.
  @discardableResult
  package static func open(
    _ folder: URL, into document: ProjectDocument?, report: (any Error) -> Void
  ) async -> LegacyRunWindow? {
    do {
      return try await open(folder, into: document)
    } catch {
      logger.error("cannot open run \(folder.path, privacy: .public): \(error, privacy: .public)")
      report(error)
      return nil
    }
  }

  /// Opens the run at `folder` in a new window and records it in the project of `document`.
  @discardableResult
  package static func open(_ folder: URL, into document: ProjectDocument?) async throws
    -> LegacyRunWindow
  {
    let model = try await LegacyRunModel.open(folder: folder)
    try document?.importLegacyRun(model.source)
    let controller = LegacyRunWindow(model: model)
    opened.append(controller)
    controller.showWindow(nil)
    return controller
  }

  private init(model: LegacyRunModel) {
    self.model = model
    let window = NSWindow(
      contentRect: SplitWindow.contentRect(panes: NSSize(width: 1400, height: 860)),
      styleMask: SplitWindow.styleMask, backing: .buffered,
      defer: false)
    window.title = model.title
    window.contentView = NSHostingView(rootView: LegacyRunView(model: model).interfaceLocale())
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  package func windowWillClose(_ notification: Notification) {
    Self.opened.removeAll { $0 === self }
  }
}
