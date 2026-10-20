internal import Foundation

/// Finds a legacy run's layers by file name: `rgb_base` as the colour base when present, then
/// each channel's best file by `LayerPrecedence`, a dual-band channel replaced by its `syn_*`
/// lines.
enum LegacyLayerDiscovery {
  /// The layers in `folder`, base first then canonical filter order, with `frames` (channel →
  /// frames) attached.
  static func layers(
    in folder: URL, frames: [String: Int]
  ) throws -> [LegacyRunSource.Layer] {
    let bases = Set(
      try FileManager.default.contentsOfDirectory(atPath: folder.path)
        .filter { $0.hasSuffix(".fits") }.map { String($0.dropLast(5)) })
    var layers: [LegacyRunSource.Layer] = []
    let hasBase = bases.contains("rgb_base")
    if hasBase {
      layers.append(
        LegacyRunSource.Layer(
          id: Filter.color, role: .rgb, file: "rgb_base.fits", source: "rgb_base",
          frames: frames[Filter.color]))
    }
    let tags = Set(bases.compactMap(LayerPrecedence.tag(of:)))
    for tag in ChannelAligner.ordered(tags) where !isDualBand(tag) {
      let role = LinearBundle.Role(filter: tag)
      if role == .rgb && hasBase { continue }
      guard let best = LayerPrecedence.best(for: tag, among: bases) else { continue }
      layers.append(
        LegacyRunSource.Layer(
          id: tag, role: role, file: best.base + ".fits", source: best.stage,
          frames: LegacyRunRecord.frames(for: tag, source: best.stage, in: frames)))
    }
    // The colour base first, then lum/red/green/blue, then lines: the panel's order.
    let rank: [LinearBundle.Role: Int] = [.rgb: 0, .lum: 1, .red: 2, .green: 3, .blue: 4, .line: 5]
    return layers.enumerated()
      .sorted { (rank[$0.element.role] ?? 9, $0.offset) < (rank[$1.element.role] ?? 9, $1.offset) }
      .map(\.element)
  }

  /// A dual-band OSC channel (`RGB-dualband`): its lines are the run's `syn_*` layers.
  static func isDualBand(_ tag: String) -> Bool {
    tag.lowercased().hasSuffix("dualband")
  }
}
