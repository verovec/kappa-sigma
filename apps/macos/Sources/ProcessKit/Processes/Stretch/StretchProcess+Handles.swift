package import RenderKit

extension StretchProcess: HistogramHandled {
  /// The mappings of the head's statistics the MTF mode reads: the mean when linked.
  private static func mappings(_ params: ParamSet, stats: LayerStats, channels: Int)
    -> [STFMapping]
  {
    let own = stats.channels.prefix(max(channels, 1))
      .map { STFMapping(median: $0.median, madn: $0.madn) }
    return params.flag("linked") ? Array(STFMapping.linked(own).prefix(1)) : own
  }

  /// The MTF mode's black point and midtone on the input histogram (c1 = 1); no handle in the
  /// GHS and asinh modes.
  package static func handles(_ params: ParamSet, stats: LayerStats, channels: Int)
    -> [STFHandlePositions]
  {
    guard params.choice("mode") == "mtf" else { return [] }
    let (clip, target) = (params.number("shadowsClip"), params.number("targetBackground"))
    return mappings(params, stats: stats, channels: channels).map {
      $0.parameters(sigma: clip, targetBackground: target).handlePositions(in: .linear)
    }
  }

  /// The black point sets the σ of the shadows clip, the midtone the target background, as the
  /// viewer's controls read them (`STFMapping`); the white point is fixed at 1 (not a value).
  package static func dragging(
    _ handle: STFHandle, channel: Int, to position: Double, params: ParamSet, stats: LayerStats
  ) throws -> ParamSet {
    let all = mappings(params, stats: stats, channels: stats.channels.count)
    guard params.choice("mode") == "mtf", handle != .highlights, all.indices.contains(channel)
    else { return params }
    let mapping = all[channel]
    let (clip, target) = (params.number("shadowsClip"), params.number("targetBackground"))
    let stf = mapping.parameters(sigma: clip, targetBackground: target)
    let moved = stf.dragging(handle, to: position, in: .linear)
    var params = params
    switch handle {
    case .shadows:
      try params.set("shadowsClip", .number(mapping.sigma(ofShadows: moved.shadows)))
    case .midtone:
      try params.set(
        "targetBackground",
        .number(mapping.targetBackground(ofMidtone: moved.midtone, shadows: moved.shadows)))
    case .highlights:
      break
    }
    return params
  }
}
