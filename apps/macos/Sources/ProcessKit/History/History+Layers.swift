package import Foundation
package import ImageKit

// MARK: - Step layers (cards 0091, 0092)

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
    try writtenFiles.mapValues(layer(file:))
  }

  /// The layer the applied steps last wrote under `id` (a role's raw value or a bundle id), or
  /// `nil`: one file read, not the whole overlay.
  package func writtenLayer(_ id: String) throws -> AstroImage? {
    try writtenFiles[id].map(layer(file:))
  }

  /// The file each written layer id last went to, without reading it: the one overlay rule,
  /// and the key of a cached overlay.
  package var writtenFiles: [String: String] {
    var latest: [String: String] = [:]
    for step in steps {
      latest.merge(step.replaced) { _, newer in newer }
      latest.merge(step.outputs.map { ($0.key.rawValue, $0.value) }) { _, newer in newer }
    }
    return latest
  }

  /// The file of the latest layer of each role the applied steps wrote (`writtenFiles` of the
  /// role outputs).
  package var layerFiles: [LayerRole: String] {
    var roles: [LayerRole: String] = [:]
    for (id, file) in writtenFiles {
      if let role = LayerRole(rawValue: id) { roles[role] = file }
    }
    return roles
  }

  /// The file of the latest layer of `role` the applied steps wrote, or `nil`: read where the
  /// caller wants (a 22 Mpx layer is ~260 MB to decode).
  package func layerFile(_ role: LayerRole) -> URL? {
    layerFiles[role].map(directory.appendingPathComponent)
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

  /// The layers step `index` wrote by role, read from disk.
  package func outputs(ofStep index: Int) throws -> [LayerRole: AstroImage] {
    try written(ofStep: index).outputs
  }

  func layer(file: String) throws -> AstroImage {
    if let cached = layerCache[file] { return Self.copy(cached) }
    let image = try FITSFile.read(at: directory.appendingPathComponent(file)).image()
    layerCache[file] = image
    return Self.copy(image)
  }
}
