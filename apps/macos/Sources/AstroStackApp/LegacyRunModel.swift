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
  /// The selected layer's id.
  package private(set) var selected: String?
  /// The selected layer, once loaded.
  package private(set) var viewer: Viewer?

  /// Opens the run at `folder` (read-only; headers only until a layer is selected).
  package init(folder: URL) throws {
    source = try LegacyRunSource(folder: folder)
  }

  /// "M_31 · 20261018_191749".
  package var title: String { "\(source.object) · \(source.runID)" }

  /// Role, file, size and frames of every layer, base first.
  package var rows: [Row] {
    source.layers.map { layer in
      var parts = [
        layer.role.rawValue, layer.file, "\(source.grid.width)×\(source.grid.height)",
      ]
      if let frames = layer.frames { parts.append("\(frames) frames") }
      return Row(name: layer.id, detail: parts.joined(separator: " · "))
    }
  }

  /// Loads layer `id` off the main actor and shows it.
  package func select(_ id: String) async throws {
    guard let layer = source.layers.first(where: { $0.id == id }) else { return }
    guard id != selected || viewer == nil else { return }  // already shown
    guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
    selected = id
    let renderer = try ViewerRenderer(device: device)
    let loaded = try await LoadedImage.read(
      source.folder.appendingPathComponent(layer.file), device: device)
    try Task.checkCancellation()
    guard selected == id else { return }  // another layer was chosen meanwhile
    viewer = Viewer(
      model: ViewerModel(image: loaded.image, autoSTF: loaded.autoSTF), renderer: renderer,
      texture: loaded.texture)
  }
}
