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

    /// A layer input.
    package init(filter: String, file: URL, source: String) {
      self.filter = filter
      self.file = file
      self.source = source
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
    let sizes = try layers.map { input -> (Input, FITSFile, Int, Int) in
      let file = try FITSFile.read(at: input.file)
      let layout = (file.header.int("NAXIS1") ?? 0, file.header.int("NAXIS2") ?? 0)
      return (input, file, layout.0, layout.1)
    }
    guard let first = sizes.first else { throw PreprocessError.noChannels([]) }
    guard sizes.allSatisfy({ $0.2 == first.2 && $0.3 == first.3 }) else {
      throw PreprocessError.mixedDimensions(sizes.map { "\($0.0.filter) \($0.2)×\($0.3)" })
    }
    let measured = try sizes.map { input, file, _, _ in
      LinearBundle.Layer(
        id: input.filter, role: LinearBundle.Role(filter: input.filter),
        file: input.file.lastPathComponent, source: input.source,
        stats: LayerStats.measure(try file.image().planes))
    }
    let bundle = LinearBundle(
      runID: runID, colorModel: colorModel, grid: .init(width: first.2, height: first.3), layers: measured)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(bundle).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    return bundle
  }

  /// The bundle in `folder`.
  package static func read(from folder: URL) throws -> LinearBundle {
    try JSONDecoder().decode(
      LinearBundle.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
  }
}
