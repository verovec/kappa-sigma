internal import Foundation

extension InventoryBuilder {
  /// Types the frames header, names and manifests left unknown from their pixel curves, compared
  /// across the folder (`classifyUnknowns`).
  ///
  /// A frame with no curve and no capture metadata at all is a processed leftover and stays
  /// unknown.
  func classifyUnknowns(_ inventory: inout Inventory) throws {
    let unknown = inventory.frames.indices.filter { inventory.frames[$0].type == .unknown }
    guard !unknown.isEmpty else { return }
    let stats = try unknown.map { index in
      try Task.checkCancellation()
      let frame = inventory.frames[index]
      return pixels.stats(frame.path, sample: Self.statsSample)?.frameStat(
        exposureMs: frame.exposureMs)
        ?? FrameStat(exposureMs: frame.exposureMs, measured: false)
    }
    let types = FrameClassifier.byStats(stats)
    for (position, index) in unknown.enumerated() {
      let frame = inventory.frames[index]
      let stat = stats[position]
      let name = InspectWalk.relative(frame.path, to: inventory.root)
      if !stat.measured && frame.exposureMs == 0 && !frame.hasGain && frame.dateObs.isEmpty {
        inventory.warnings.append(
          "\(name) has no type, no capture metadata and unreadable pixels — "
            + "skipped as a processed leftover"
        )
        continue
      }
      inventory.frames[index].type = types[position]
      inventory.frames[index].classSource = .heuristic
      // One-shot-colour frames routinely omit IMAGETYP: not worth a warning per frame.
      guard frame.bayer.isEmpty else { continue }
      guard stat.measured else {
        inventory.warnings.append(
          "\(name) has no IMAGETYP/type folder and its pixels could not be sampled — kept as LIGHT")
        continue
      }
      inventory.warnings.append(
        "\(name) has no IMAGETYP/type folder; classified as \(types[position].rawValue) by curve "
          + "heuristic (median \(String(format: "%.0f", stat.median)), peaks \(stat.peaks))")
    }
  }
}

extension Inventory {
  /// Warns about the calibration a folder lacks (`addWarnings`).
  mutating func addCompletenessWarnings() {
    let counts = countsByType
    let lights = counts[.light] ?? 0
    guard lights > 0 else {
      warnings.append("no light frames or videos found")
      return
    }
    let darks = counts[.dark] ?? 0
    if darks == 0 {
      warnings.append(
        "no darks in this folder — a matching master from the calibration library will be used if "
          + "there is one, otherwise dark calibration is skipped")
    }
    if (counts[.flat] ?? 0) == 0 {
      warnings.append(
        "no flats in this folder — a matching master from the calibration library will be used if "
          + "there is one, otherwise vignetting/dust correction is skipped")
    }
    if (counts[.bias] ?? 0) == 0 && darks == 0 {
      warnings.append("no bias or dark frames found — no read-noise calibration available")
    }
  }
}
