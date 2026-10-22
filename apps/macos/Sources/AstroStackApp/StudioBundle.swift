internal import Foundation
package import ImageKit
package import ProcessKit
package import StackKit

/// A stack's layers as the Studio runs on them (card 0087): every layer FITS read at the
/// stack's size, its statistics, and the layer roles a process's `requires` is checked against.
package enum StudioBundle {
  /// The bundle of `source` and its roles, read off the main actor (hundreds of MB).
  @concurrent
  package nonisolated static func load(_ source: LegacyRunSource) async throws
    -> (bundle: PipelineBundle, roles: Set<LayerRole>, header: FITSHeader?)
  {
    var layers: [String: AstroImage] = [:]
    var stats: [String: LayerStats] = [:]
    var roles: Set<LayerRole> = []
    var headers: [String: FITSHeader] = [:]
    for layer in source.layers {
      try Task.checkCancellation()
      let file = try FITSFile.read(at: source.url(of: layer))
      let image = try file.image()
      headers[layer.id] = file.header
      let fitted = source.bundle?.layers.first { $0.id == layer.id }
      let measured = StudioSession.stats(of: image)
      stats[layer.id] = LayerStats(
        channels: measured.channels, continuumK: fitted?.continuumK,
        continuumReference: fitted?.continuumReference)
      layers[layer.id] = image
      roles.insert(role(of: layer.role))
    }
    guard let base = StudioSession.baseLayerID(layers.keys), let baseStats = stats[base] else {
      throw StudioError.emptyBundle
    }
    return (
      PipelineBundle(stats: baseStats, layers: layers, layerStats: stats), roles, headers[base]
    )
  }

  /// The Studio role of a bundle role: colour planes are the colour base, L the luminance, any
  /// other filter an emission line.
  package nonisolated static func role(of role: LinearBundle.Role) -> LayerRole {
    switch role {
    case .rgb, .red, .green, .blue: .color
    case .lum: .luminance
    case .line: .emission
    }
  }
}
