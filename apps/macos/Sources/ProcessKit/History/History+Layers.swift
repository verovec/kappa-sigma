internal import Foundation
package import ImageKit

extension History {
  /// The layers the next step reads: `bundle` by id, overlaid by `writtenLayers()`.
  package func context(over bundle: [String: AstroImage]) throws -> [String: AstroImage] {
    try bundle.merging(writtenLayers()) { _, written in written }
  }

  /// The layers the applied steps wrote, by context id, the latest of each id winning.
  ///
  /// The bundle layers they rewrote are under the bundle's id, their role outputs under
  /// `role.rawValue`. Each file is read from disk once (every live preview asks), handed out as
  /// a copy.
  package func writtenLayers() throws -> [String: AstroImage] {
    var latest: [String: String] = [:]
    for step in steps {
      latest.merge(step.replaced) { _, newer in newer }
      latest.merge(step.outputs.map { ($0.key.rawValue, $0.value) }) { _, newer in newer }
    }
    return try latest.mapValues(layer(file:))
  }

  /// What applied step `index` wrote besides its image: its role outputs and the bundle layers
  /// it rewrote (a locked pipeline step reused on replay carries them over).
  package func written(ofStep index: Int) throws
    -> (outputs: [LayerRole: AstroImage], replaced: [String: AstroImage])
  {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    let step = steps[index]
    return (try step.outputs.mapValues(layer(file:)), try step.replaced.mapValues(layer(file:)))
  }

  func layer(file: String) throws -> AstroImage {
    if let cached = layerCache[file] { return Self.copy(cached) }
    let image = try FITSFile.read(at: directory.appendingPathComponent(file)).image()
    layerCache[file] = image
    return Self.copy(image)
  }
}
