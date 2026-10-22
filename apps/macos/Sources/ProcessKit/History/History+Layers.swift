package import Foundation
package import ImageKit

// MARK: - Step layers (card 0091)

extension History {
  /// The file of the latest layer of `role` the applied steps wrote, or `nil`: read where the
  /// caller wants (a 22 Mpx layer is ~260 MB to decode).
  package func layerFile(_ role: LayerRole) -> URL? {
    steps.last { $0.outputs[role] != nil }?.outputs[role].map(directory.appendingPathComponent)
  }

  /// The file of the latest layer of each role the applied steps wrote: what `layers()` reads,
  /// without reading it (a cache key).
  package var layerFiles: [LayerRole: String] {
    var latest: [LayerRole: String] = [:]
    for step in steps { latest.merge(step.outputs) { _, newer in newer } }
    return latest
  }

  /// The layers step `index` wrote, read from disk: what a reused locked step writes again.
  package func outputs(ofStep index: Int) throws -> [LayerRole: AstroImage] {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    return try steps[index].outputs.mapValues {
      try FITSFile.read(at: directory.appendingPathComponent($0)).image()
    }
  }
}
