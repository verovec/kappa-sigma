package import RenderKit

extension LevelsProcess: HistogramHandled {
  /// The triple a channel's handles move: RGB/K when linked (one set), else the channel's own.
  static func triple(channel: Int, params: ParamSet, channels: Int) -> String {
    params.flag("linked") || channels < 3 ? "rgb" : triples[1 + min(channel, 2)]
  }

  /// One set when linked or mono, one per channel otherwise.
  package static func handles(_ params: ParamSet, stats: LayerStats, channels: Int)
    -> [STFHandlePositions]
  {
    let count = params.flag("linked") || channels < 3 ? 1 : 3
    return (0..<count).map { channel in
      stf(triple(channel: channel, params: params, channels: channels), of: params)
        .handlePositions(in: .linear)
    }
  }

  /// The handle's value moves (`STFParameters.dragging`: c0 + range ≤ c1, m between them).
  package static func dragging(
    _ handle: STFHandle, channel: Int, to position: Double, params: ParamSet, stats: LayerStats
  ) throws -> ParamSet {
    let triple = triple(channel: channel, params: params, channels: 3)
    let moved = stf(triple, of: params).dragging(handle, to: position, in: .linear)
    return try setting(moved, as: triple, on: params)
  }
}

extension LevelsProcess {
  /// Arrow steps: 0.001 on the black and white points (0.0001 fine), 0.01 on the midtones
  /// (0.001 fine), 0.001 on the output range.
  package static var steps: [String: Double] {
    var steps = ["outputLow": 0.001, "outputHigh": 0.001]
    for triple in triples {
      steps[triple + "Shadows"] = 0.001
      steps[triple + "Midtones"] = 0.01
      steps[triple + "Highlights"] = 0.001
    }
    return steps
  }

  /// The value `x` of `channel` (of `channels` planes) through the triples, before the output
  /// range, in double (`STFParameters.display`): the clipping readouts measure it.
  package static func transfer(_ x: Double, channel: Int, channels: Int, params: ParamSet)
    -> Double
  {
    var value = x
    if !params.flag("linked"), channels == 3 {
      let own = stf(triples[1 + min(channel, 2)], of: params)
      if own != .identity { value = own.display(value) }
    }
    let rgb = stf("rgb", of: params)
    return rgb == .identity ? value : rgb.display(value)
  }
}
