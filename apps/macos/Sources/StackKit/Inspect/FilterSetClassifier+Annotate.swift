internal import Accelerate

extension FilterSetClassifier {
  /// Stamps a verdict on every one-shot-colour LIGHT set (`annotateFilterSets`): a bounded sample
  /// of frames per set, the scan's own bias pedestal subtracted.
  ///
  /// Without a bias or dark there is no honest answer. Overrides win outright, even where nothing
  /// was measured.
  package static func annotate(
    _ inventory: inout Inventory, overrides: [String: FilterSet], pixels: PixelReader
  ) {
    var verdicts: [String: FilterSet] = [:]
    if inventory.colorModel == .osc, let floor = biasFloor(inventory.sets, pixels: pixels) {
      for set in inventory.sets where set.key.type == .light {
        let verdict = classify(set, floor: floor, pixels: pixels)
        if verdict.isKnown { verdicts[set.key.id] = verdict }
      }
    }
    for (id, verdict) in overrides where verdict.isKnown { verdicts[id] = verdict }
    inventory.filterSets = verdicts
    inventory.applyFilterSets()
  }

  /// The median of the sampled frames' skies, above the floor, at the set's EGAIN: one frame
  /// ruined by a cloud must not move a night's verdict.
  private static func classify(_ set: FrameSet, floor: Double, pixels: PixelReader) -> FilterSet {
    let skies = sample(set.frames, count: sampleFrames).compactMap { sky(of: $0, pixels: pixels) }
    guard !skies.isEmpty else { return .unknown }
    let above = ChannelSky(
      r: median(skies.map(\.r)) - floor, g: median(skies.map(\.g)) - floor,
      b: median(skies.map(\.b)) - floor)
    let eGains = set.frames.map(\.eGain).filter { $0 > 0 }
    return classify(
      above, exposureMs: set.key.exposureMs, eGain: eGains.isEmpty ? 0 : median(eGains))
  }

  /// The electronic pedestal: the BIAS frames' level, else the DARKs' (slightly high, which
  /// leans the amplitude toward dual-band; the colour test still has to agree).
  private static func biasFloor(_ sets: [FrameSet], pixels: PixelReader) -> Double? {
    for type in [FrameType.bias, .dark] {
      let levels = sets.filter { $0.key.type == type }
        .flatMap { sample($0.frames, count: sampleFrames) }
        .compactMap { sky(of: $0, pixels: pixels)?.amplitude }
      if !levels.isEmpty { return median(levels) }
    }
    return nil
  }

  /// One frame's per-channel level in 16-bit ADU: a mosaic at its Bayer positions, a debayered
  /// frame by plane; Siril's [0,1] floats scaled back to ADU.
  static func sky(of frame: CaptureFrame, pixels: PixelReader) -> ChannelSky? {
    guard let image = try? pixels.planes(frame.path), image.width > 0, image.height > 0,
      let first = image.planes.first, !first.isEmpty
    else { return nil }
    let sky =
      image.planes.count >= 3
      ? planeSky(image.planes)
      : cfaSky(first, width: image.width, height: image.height, pattern: frame.bayer)
    guard let sky else { return nil }
    // A real frame always has something above 1 ADU (a star, the pedestal): all ≤ 1 is normalized.
    let normalized = image.planes.allSatisfy { $0.isEmpty || vDSP.maximum($0) <= 1 }
    return normalized ? sky.scaled(65535) : sky
  }

  /// Up to `count` frames spread across the set, so the first subs cannot define the night.
  static func sample<Element>(_ items: [Element], count: Int) -> [Element] {
    guard items.count > count else { return items }
    let step = Double(items.count) / Double(count)
    return (0..<count).map { items[Int(Double($0) * step)] }
  }

  /// The upper-middle order statistic, as the legacy engine took it.
  static func median(_ values: [Double]) -> Double {
    values.sorted()[values.count / 2]
  }
}
