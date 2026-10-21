package import Metal
package import RenderKit

/// Manual colour balance on linear data: a per-channel background offset and RGB gains,
/// `out = (in + offset) · gain`.
///
/// Card 0053 (review of 2026-10-20): when SPCC/PCC fails (the 20 mm field) or is invalid
/// (dual-band), this is the user's manual route. R2: a sky region the user draws is measured
/// (`regionMedians`) and only fills suggestions — offsets that equalise its medians, or gains
/// that make it grey; the panel shows and applies the offsets and gains, nothing else. Linking
/// the gains is a panel behaviour (one slider moves the three values it shows), never a hidden
/// override in `render`.
package struct ColourBalanceProcess: ImageProcess {
  package static let id = "colour-balance"
  package static let title = "Colour balance"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = false
  private static let channels = ["Red", "Green", "Blue"]

  package static let schema = ParamSchema(
    channels.map {
      ParamSpec(
        id: "offset" + $0, title: $0 + " background offset", unit: .none, level: .simple,
        number: 0, in: -0.5...0.5)
    }
      + channels.map {
        ParamSpec(
          id: "gain" + $0, title: $0 + " gain", unit: .none, level: .simple, number: 1,
          in: 0.1...10)
      })

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ColourKernel.pipeline(device: device, function: "colourBalance")
  }

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "neutralises the sky region: its three medians become equal",
    "makes the sky region grey: green kept, red and blue scaled to it",
  ]

  /// Offsets bringing each channel's median of the region to the mean of the three (the
  /// background level is kept).
  package static func neutraliseSuggestions(regionMedians: [Double]) -> [Suggestion] {
    guard regionMedians.count == 3 else { return [] }
    let mean = regionMedians.reduce(0, +) / 3
    return zip(channels, regionMedians).map {
      Suggestion(
        paramID: "offset" + $0, value: .number(mean - $1), reason: suggestionReasons[0])
    }
  }

  /// Gains making the region grey after the current offsets, green fixed.
  ///
  /// g = (m_G + o_G) / (m_c + o_c); empty when a channel's level is not positive or a gain would
  /// leave the parameter's bounds (applying it would clamp it: shown ≠ applied).
  package static func greySuggestions(regionMedians: [Double], params: ParamSet) -> [Suggestion] {
    guard regionMedians.count == 3 else { return [] }
    let levels = zip(channels, regionMedians).map { $1 + params.number("offset" + $0) }
    guard levels.allSatisfy({ $0 > 0 }) else { return [] }
    let gains = levels.map { levels[1] / $0 }
    guard case .number(_, let bounds)? = schema.spec("gainRed")?.kind,
      gains.allSatisfy(bounds.contains)
    else { return [] }
    return zip(channels, levels).map {
      Suggestion(
        paramID: "gain" + $0, value: .number(levels[1] / $1), reason: suggestionReasons[1])
    }
  }

  /// The median of each plane of `image` inside `region` (RenderKit's robust median), what the
  /// suggestions start from.
  package static func regionMedians(_ image: GPUImage, region: PixelRegion) throws -> [Double] {
    guard region.width > 0, region.height > 0, region.x >= 0, region.y >= 0,
      region.x + region.width <= image.width, region.y + region.height <= image.height
    else {
      throw ProcessError.invalidParameter("the sky region must lie inside the image")
    }
    // Only the region comes back from the GPU, never the whole frame.
    let box = MTLRegionMake2D(region.x, region.y, region.width, region.height)
    let pixels = region.width * region.height
    return image.planes.map { plane in
      let values = unsafe [Float](unsafeUninitializedCapacity: pixels) { buffer, count in
        guard let base = buffer.baseAddress else { return }
        unsafe plane.getBytes(
          base, bytesPerRow: region.width * MemoryLayout<Float>.stride, from: box, mipmapLevel: 0)
        count = pixels
      }
      return AutoSTF.medianAndMADN(values).median
    }
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.checkSizes(input, output)
    let offsets = Self.channels.map { params.number("offset" + $0) }
    let gains = Self.channels.map { params.number("gain" + $0) }
    // A balance between channels has no meaning on one plane, and untouched values change no
    // bit (not even −0.0): both go through as they are.
    guard input.planes.count == 3, offsets != [0, 0, 0] || gains != [1, 1, 1] else {
      return try ColourKernel.copy(input, into: output, commands: context.commands)
    }
    let values = (offsets + gains).map { Float($0) }
    try ColourKernel.encode(
      pipeline, input, into: output, values: values, commands: context.commands)
  }
}
