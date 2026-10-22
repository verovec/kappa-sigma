package import Foundation
import Metal
import Observation
package import RenderKit
package import StackKit

/// A legacy run window's state: the layers the sidebar lists and the one shown in the viewer.
@Observable
package final class LegacyRunModel {
  /// One sidebar row.
  package struct Row: Identifiable, Equatable {
    /// The layer id (`RGB`, `Ha`, …).
    package let name: String
    /// Role, file, size and frames.
    package let detail: String
    package var id: String { name }
  }

  /// A layer loaded for the viewer.
  package struct Viewer {
    /// The viewer state.
    package let model: ViewerModel
    let renderer: ViewerRenderer
    let texture: ImageTexture
  }

  /// The opened run.
  package let source: LegacyRunSource
  /// The layer shown in the viewer.
  package private(set) var selected: String?
  /// The shown layer, once loaded.
  package private(set) var viewer: Viewer?
  /// Why the last chosen layer could not be shown (the previous one stays).
  package private(set) var failure: LocalizedStringResource?
  @ObservationIgnored private var renderer: ViewerRenderer?

  /// A model of the run `source` (already opened).
  package init(source: LegacyRunSource) {
    self.source = source
  }

  /// Opens the run at `folder` off the main actor: listing, JSON and FITS headers.
  package static func open(folder: URL) async throws -> LegacyRunModel {
    LegacyRunModel(source: try await read(folder))
  }

  @concurrent
  private nonisolated static func read(_ folder: URL) async throws -> LegacyRunSource {
    try LegacyRunSource(folder: folder)
  }

  /// "M_31 · 20261018_191749".
  package var title: String { "\(source.object) · \(source.runID)" }

  /// Role, file, size and frames of every layer, base first, worded in `locale`.
  package func rows(locale: Locale) -> [Row] {
    let format = AstroFormat(locale: locale)
    return source.layers.map { layer in
      var parts = [
        AppGlossary.label(layer.role.termID, locale: locale), layer.file,
        "\(source.grid.width)×\(source.grid.height)",
      ]
      if let frames = layer.frames { parts.append(format.frames(frames)) }
      return Row(name: layer.id, detail: parts.joined(separator: " · "))
    }
  }

  /// Loads layer `id` off the main actor and shows it.
  ///
  /// A failure keeps the layer shown before and is reported (`failure`), so choosing the layer
  /// again retries.
  package func select(_ id: String) async throws {
    guard id != selected || viewer == nil else { return }  // already shown
    guard let layer = source.layers.first(where: { $0.id == id }) else { return }
    do {
      let renderer = try self.renderer ?? Self.makeRenderer()
      self.renderer = renderer
      let loaded = try await LoadedImage.read(source.url(of: layer), device: renderer.device)
      try Task.checkCancellation()
      selected = id
      failure = nil
      viewer = Viewer(
        model: ViewerModel(image: loaded.image, statistics: loaded.statistics), renderer: renderer,
        texture: loaded.texture)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      failure = .app("\(layer.file): \(UserFacingError(error).message)")
      throw error
    }
  }

  /// One renderer for the window: its pipelines are compiled once, not per layer.
  private static func makeRenderer() throws -> ViewerRenderer {
    guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
    return try ViewerRenderer(device: device)
  }
}
