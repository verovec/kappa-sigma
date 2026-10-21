package import Foundation
internal import ImageKit

/// Writes a run's `bundle.json` beside its layers: one grid or nothing, stats measured on every
/// pixel, the file replaced atomically.
package struct BundleWriter: Sendable {
  /// One layer to record: a channel's filter, its FITS file and the stage that wrote it.
  package struct Input: Sendable {
    package var filter: String
    package var file: URL
    package var source: String
    /// A line layer's continuum scale (`ContinuumK`), when fitted.
    package var continuumK: Double?
    /// The plane that scale was fitted against (`ContinuumK.Fit.plane`).
    package var continuumReference: String?

    /// A layer input.
    package init(
      filter: String, file: URL, source: String, continuumK: Double? = nil,
      continuumReference: String? = nil
    ) {
      self.filter = filter
      self.file = file
      self.source = source
      self.continuumK = continuumK
      self.continuumReference = continuumReference
    }
  }

  /// The bundle file's name.
  package static let fileName = "bundle.json"

  /// A writer.
  package init() {}

  /// Measures `layers` and writes `folder/bundle.json`; mixed dimensions are refused before
  /// anything is written.
  @discardableResult
  package func write(runID: String, colorModel: ColorModel, layers: [Input], to folder: URL) throws
    -> LinearBundle
  {
    let bundle = try measure(runID: runID, colorModel: colorModel, layers: layers)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(bundle).write(
      to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    return bundle
  }

  /// The bundle of `layers` without writing it (a legacy run is read-only): one grid, stats on
  /// every pixel.
  package func measure(runID: String, colorModel: ColorModel, layers: [Input]) throws
    -> LinearBundle
  {
    let files = try layers.map { (input: $0, file: try FITSFile.read(at: $0.file)) }
    let grids = files.map { entry in
      LinearBundle.Grid(
        width: entry.file.header.int("NAXIS1") ?? 0, height: entry.file.header.int("NAXIS2") ?? 0)
    }
    guard let grid = grids.first else { throw PreprocessError.noChannels([]) }
    guard grids.allSatisfy({ $0 == grid }) else {
      throw PreprocessError.mixedDimensions(
        zip(layers, grids).map { "\($0.filter) \($1.width)×\($1.height)" })
    }
    let measured = try files.map { input, file in
      LinearBundle.Layer(
        id: input.filter, role: LinearBundle.Role(filter: input.filter),
        file: input.file.lastPathComponent, source: input.source,
        stats: LayerStats.measure(try file.image().planes), continuumK: input.continuumK,
        continuumReference: input.continuumReference)
    }
    return LinearBundle(runID: runID, colorModel: colorModel, grid: grid, layers: measured)
  }

  /// The bundle in `folder`.
  package static func read(from folder: URL) throws -> LinearBundle {
    try JSONDecoder().decode(
      LinearBundle.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
  }
}
