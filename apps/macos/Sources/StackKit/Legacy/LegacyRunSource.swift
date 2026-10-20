package import Foundation
internal import ImageKit
package import ProjectKit

/// A finished legacy run (`~/Documents/astro/runs/<Object>/<run_id>/`) opened read-only as a
/// project source.
///
/// The layers come from the run's `bundle.json` when this app wrote one, else from discovery by
/// `LayerPrecedence` (the legacy `reconstructChannelsFromDisk` rule). `rgb_base.fits` is the
/// post-headroom linear base and `syn_*` are lines split from a dual-band channel. Nothing in
/// the folder is ever written (R7): files are only read.
package struct LegacyRunSource: Sendable {
  /// One layer of the run.
  package struct Layer: Equatable, Sendable {
    /// The channel (`RGB`, `L`, `R`, `G`, `B`, `Ha`, `OIII`, `SII`…).
    package let id: String
    /// What it is to the Studio.
    package let role: LinearBundle.Role
    /// The FITS file, relative to the run folder.
    package let file: String
    /// `rgb_base`, `trim`, `combine`, `aligned`, `master` or `syn`.
    package let source: String
    /// Frames stacked into it (`run.json` channels), when recorded.
    package let frames: Int?
  }

  /// The run folder.
  package let folder: URL
  /// The legacy run id.
  package let runID: String
  /// The target.
  package let object: String
  /// Mono or one-shot colour (`stages.json` preset).
  package let colorModel: ColorModel
  /// The layers, base first then the canonical filter order.
  package let layers: [Layer]
  /// The run's own bundle, when this app wrote one.
  package let bundle: LinearBundle?
  /// Where the layer files are: the folder holding `bundle.json` (the run, or its `linear/`).
  package let layerFolder: URL
  /// The pixel grid every layer shares.
  package let grid: LinearBundle.Grid

  /// Opens the run in `folder`.
  ///
  /// Parses `run.json` and `stages.json`, finds the layers and checks they share one grid. Throws `LegacyRunError` for a folder that is not a run, has no layer, or mixes sizes.
  package init(folder: URL) throws {
    let run = try LegacyRunRecord.read(folder)
    self.folder = folder
    runID = run.runID
    object = run.object
    colorModel = run.colorModel
    let own = Self.ownBundle(in: folder)
    bundle = own?.bundle
    layerFolder = own?.folder ?? folder
    if let bundle {
      layers = bundle.layers.map {
        Layer(
          id: $0.id, role: $0.role, file: $0.file, source: $0.source,
          frames: run.frames(for: $0.id, source: $0.source))
      }
    } else {
      layers = try LegacyLayerDiscovery.layers(in: folder, frames: run.frames)
    }
    guard !layers.isEmpty else { throw LegacyRunError.noLayers(folder.path) }
    grid = try Self.checkGrid(layers, in: layerFolder)
  }

  /// Records the run in the project: its path only, read-only (no layer is copied).
  @discardableResult
  package func record(in store: ProjectStore) throws -> ProjectSource {
    try store.addSource(kind: .legacyRun, path: folder.standardizedFileURL.path)
  }

  /// The file of `layer`.
  package func url(of layer: Layer) -> URL {
    layerFolder.appendingPathComponent(layer.file)
  }

  /// `bundle.json` at the run's root or in `linear/` (an app-made stack) and its folder.
  private static func ownBundle(in folder: URL) -> (bundle: LinearBundle, folder: URL)? {
    for candidate in [folder, folder.appendingPathComponent("linear")] {
      if let bundle = try? BundleWriter.read(from: candidate) { return (bundle, candidate) }
    }
    return nil
  }

  /// One grid for every layer (FITS headers only), or the list of every layer and its size.
  private static func checkGrid(_ layers: [Layer], in folder: URL) throws -> LinearBundle.Grid {
    let sizes = try layers.map { layer -> (String, Int, Int) in
      let header = try FITSFile.read(at: folder.appendingPathComponent(layer.file)).header
      return (layer.id, header.int("NAXIS1") ?? 0, header.int("NAXIS2") ?? 0)
    }
    guard let first = sizes.first, sizes.allSatisfy({ $0.1 == first.1 && $0.2 == first.2 }) else {
      throw LegacyRunError.mixedDimensions(sizes.map { "\($0.0) \($0.1)×\($0.2)" })
    }
    return LinearBundle.Grid(width: first.1, height: first.2)
  }
}

extension LinearBundle {
  /// The bundle of a legacy run: its own `bundle.json` when it has one, else the layers measured
  /// exactly as the 0048 writer measures them (`BundleWriter.measure`), nothing written.
  package static func build(fromLegacyRun source: LegacyRunSource) throws -> LinearBundle {
    if let bundle = source.bundle { return bundle }
    return try BundleWriter().measure(
      runID: source.runID, colorModel: source.colorModel,
      layers: source.layers.map {
        BundleWriter.Input(filter: $0.id, file: source.url(of: $0), source: $0.source)
      })
  }
}
