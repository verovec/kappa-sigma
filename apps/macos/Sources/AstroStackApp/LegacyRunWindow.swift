package import AppKit
package import Foundation
import RenderKit
package import SwiftUI
import os

/// File › Open Run…: a finished legacy run (`~/Documents/astro/runs/<Object>/<run_id>/`) opened
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
    let document = NSDocumentController.shared.currentDocument as? ProjectDocument
    Task { await open(folder, into: document) { NSAlert(error: $0).runModal() } }
  }

  /// The folder picker: folders only, starting in `~/Documents/astro/runs`.
  package static func runPanel() -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents/astro/runs")
    return panel
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
    let model = try LegacyRunModel(folder: folder)
    try document?.importLegacyRun(model.source)
    let controller = LegacyRunWindow(model: model)
    opened.append(controller)
    controller.showWindow(nil)
    return controller
  }

  private init(model: LegacyRunModel) {
    self.model = model
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = model.title
    window.contentView = NSHostingView(rootView: LegacyRunView(model: model))
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

/// The Layers sidebar and the viewer of the selected layer.
package struct LegacyRunView: View {
  let model: LegacyRunModel
  @State private var selection: String?
  @State private var error: String?

  /// The sidebar starts on the layer the model already shows (`-openRun` selects the base).
  package init(model: LegacyRunModel) {
    self.model = model
    _selection = State(initialValue: model.selected)
  }

  package var body: some View {
    NavigationSplitView {
      List(model.rows, selection: $selection) { row in
        VStack(alignment: .leading) {
          Text(row.name).font(.headline)
          Text(row.detail).font(.caption).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Layers")
      .frame(minWidth: 240)
      .task(id: selection) { await load(selection) }
    } detail: {
      if let viewer = model.viewer {
        ViewerView(
          model: viewer.model, renderer: viewer.renderer, texture: viewer.texture, reference: nil
        )
        .id(model.selected)
      } else {
        ContentUnavailableView(
          error ?? "Choose a layer", systemImage: "square.3.layers.3d",
          description: Text("Read-only: nothing in the run folder is ever written."))
      }
    }
  }

  /// Loads the chosen layer; choosing another cancels a load still running.
  private func load(_ id: String?) async {
    guard let id else { return }
    do {
      try await model.select(id)
    } catch is CancellationError {
      return
    } catch {
      self.error = "\(error)"
    }
  }
}
