internal import Foundation
package import ImageKit
package import ProcessKit
package import StackKit

/// A stack's layers as the Studio runs on them (card 0087): every layer FITS read at the
/// stack's size, its statistics, and the layer roles a process's `requires` is checked against.
package enum StudioBundle {
  /// One layer read and measured: what a child task hands back (planes, never the image class).
  private struct Read: Sendable {
    let layer: LegacyRunSource.Layer
    let width: Int
    let height: Int
    let planes: [[Float]]
    let metadata: ImageMetadata
    let header: FITSHeader
    let stats: LayerStats
  }

  /// Layers read at once: a read holds the raw FITS and its planes (hundreds of MB apiece), so
  /// the fan-out is bounded by memory, not by cores.
  nonisolated static let readsInFlight = 2

  /// The bundle of `source` and its roles, read off the main actor (hundreds of MB).
  ///
  /// The layers are read and measured `readsInFlight` at a time (card 0187): a 26 Mpx stack's
  /// five layers open in about half the time of their sum, with two in memory at once.
  @concurrent
  package nonisolated static func load(_ source: LegacyRunSource) async throws
    -> (bundle: PipelineBundle, roles: Set<LayerRole>, header: FITSHeader?)
  {
    let reads = try await withThrowingTaskGroup(of: Read.self) { group in
      var layers = source.layers.makeIterator()
      for _ in 0..<readsInFlight {
        if let layer = layers.next() { group.addTask { try read(layer, of: source) } }
      }
      var reads: [String: Read] = [:]
      while let read = try await group.next() {
        reads[read.layer.id] = read
        if let layer = layers.next() { group.addTask { try self.read(layer, of: source) } }
      }
      return reads
    }
    var layers: [String: AstroImage] = [:]
    var stats: [String: LayerStats] = [:]
    var roles: Set<LayerRole> = []
    var headers: [String: FITSHeader] = [:]
    for read in reads.values {
      let fitted = source.bundle?.layers.first { $0.id == read.layer.id }
      stats[read.layer.id] = LayerStats(
        channels: read.stats.channels, continuumK: fitted?.continuumK,
        continuumReference: fitted?.continuumReference)
      layers[read.layer.id] = AstroImage(
        width: read.width, height: read.height, planes: read.planes, metadata: read.metadata)
      headers[read.layer.id] = read.header
      roles.insert(role(of: read.layer.role))
    }
    guard let base = StudioSession.baseLayerID(layers.keys), let baseStats = stats[base] else {
      throw StudioError.emptyBundle
    }
    return (
      PipelineBundle(stats: baseStats, layers: layers, layerStats: stats), roles, headers[base]
    )
  }

  /// `layer` of `source` read and measured; a cancelled load reads no further layer.
  private nonisolated static func read(_ layer: LegacyRunSource.Layer, of source: LegacyRunSource)
    throws -> Read
  {
    try Task.checkCancellation()
    let file = try FITSFile.read(at: source.url(of: layer))
    let image = try file.image()
    return Read(
      layer: layer, width: image.width, height: image.height, planes: image.planes,
      metadata: image.metadata, header: file.header, stats: StudioSession.stats(of: image))
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
