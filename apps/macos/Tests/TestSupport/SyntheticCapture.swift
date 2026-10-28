package import FilterKit
package import Foundation
internal import ImageKit
package import Testing

/// A capture generated at run time (card 0142): deterministic frames of a seeded star field, with
/// the headers a capture program writes, so the inventory, the preprocessing and the Studio run
/// on a mono or a one-shot-colour rig this Mac has never seen. Written in a test's scratch folder,
/// never committed (R7: nothing pixel-shaped in the repo).
package struct SyntheticCapture: Sendable {
  /// One rig and its lights.
  package enum Scenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// Mono L, R, G, B and Hα.
    case lrgbHa = "lrgb-ha"
    /// Mono Hα, [OIII], [SII].
    case sho
    /// Mono luminance alone.
    case lOnly = "l-only"
    /// One-shot colour: a broadband set and a SII + OIII clip set of the same night, the clip
    /// asserted at import (it shares the night's flats).
    case oscSIIOIII = "osc-sii-oiii"

    /// The light filters, in capture order (`RGB` for a one-shot-colour set).
    package var filters: [String] {
      switch self {
      case .lrgbHa: ["L", "R", "G", "B", "Ha"]
      case .sho: ["Ha", "OIII", "SII"]
      case .lOnly: ["L"]
      case .oscSIIOIII: [Filter.color, Filter.color]
      }
    }

    /// True for a one-shot-colour rig (a Bayer mosaic and its `BAYERPAT` card).
    package var isColour: Bool { self == .oscSIIOIII }

    /// The `INSTRUME` card's value: a camera no sensor table knows (no SPCC suggestion).
    package var instrument: String { isColour ? "Synthetic OSC" : "Synthetic Mono" }

    /// The exposure of each light set, in seconds (the clip night is longer: a set of its own).
    package var exposures: [Int] { isColour ? [120, 300] : filters.map { _ in 120 } }

    /// The clip filter the user asserts at import, by the exposure of its set.
    package var clips: [Int: FilterSet] { isColour ? [300: .dualbandSII] : [:] }

    package var testDescription: String { rawValue }
  }

  /// Frame side, pixels.
  package static let size = 256
  /// Lights per set; calibration frames per kind.
  package static let lightsPerSet = 3
  package static let framesPerMaster = 3

  package let scenario: Scenario

  package init(_ scenario: Scenario) {
    self.scenario = scenario
  }

  /// Writes every frame under `root/<scenario>/` and returns their URLs in writing order.
  @discardableResult
  package func write(under root: URL) throws -> [URL] {
    let folder = root.appendingPathComponent(scenario.rawValue)
    var urls: [URL] = []
    var index = 0
    for (filter, exposure) in zip(scenario.filters, scenario.exposures) {
      let tag = filter == Filter.color ? "RGB\(exposure)" : filter
      for frame in 0..<Self.lightsPerSet {
        urls.append(
          try frameFile(
            folder, "lights/\(tag)/Light_\(tag)_\(frame).fits",
            Kind(type: "Light Frame", filter: filter, exposure: exposure), index: index,
            pixels: light(seed: UInt64(index), filter: filter)))
        index += 1
      }
    }
    // Flats per filter, darks per exposure, one bias set: what the calibration plan matches.
    for filter in Set(scenario.filters).sorted() {
      for frame in 0..<Self.framesPerMaster {
        urls.append(
          try frameFile(
            folder, "flats/\(filter)/Flat_\(filter)_\(frame).fits",
            Kind(type: "Flat Field", filter: filter, exposure: 2), index: index,
            pixels: flat(seed: UInt64(index))))
        index += 1
      }
    }
    for exposure in Set(scenario.exposures).sorted() {
      for frame in 0..<Self.framesPerMaster {
        urls.append(
          try frameFile(
            folder, "darks/Dark_\(exposure)s_\(frame).fits",
            Kind(type: "Dark Frame", filter: "", exposure: exposure), index: index,
            pixels: uniform(0.01, seed: UInt64(index))))
        index += 1
      }
    }
    for frame in 0..<Self.framesPerMaster {
      urls.append(
        try frameFile(
          folder, "bias/Bias_\(frame).fits", Kind(type: "Bias Frame", filter: "", exposure: 0),
          index: index, pixels: uniform(0.005, seed: UInt64(index))))
      index += 1
    }
    return urls
  }

  // MARK: - Headers

  /// What a frame's header says it is.
  private struct Kind {
    let type: String
    let filter: String
    let exposure: Int
  }

  private func frameFile(
    _ folder: URL, _ relative: String, _ frame: Kind, index: Int, pixels: [Float]
  ) throws -> URL {
    let (kind, filter, exposure) = (frame.type, frame.filter, frame.exposure)
    let url = folder.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var cards = [
      FITSHeader.Card(keyword: "IMAGETYP", value: "'\(kind)'"),
      FITSHeader.Card(keyword: "EXPTIME", number: Double(exposure)),
      FITSHeader.Card(keyword: "GAIN", number: 100),
      FITSHeader.Card(keyword: "OFFSET", number: 50),
      FITSHeader.Card(keyword: "CCD-TEMP", number: -10),
      FITSHeader.Card(keyword: "XBINNING", number: 1),
      FITSHeader.Card(keyword: "YBINNING", number: 1),
      FITSHeader.Card(keyword: "EGAIN", number: 0.8),
      FITSHeader.Card(
        keyword: "INSTRUME", value: "'\(scenario.instrument)'"),
      FITSHeader.Card(keyword: "OBJECT", value: "'SYNTH'"),
      FITSHeader.Card(keyword: "DATE-OBS", value: "'\(Self.dateObs(index))'"),
    ]
    // A one-shot-colour light carries no filter: its clip is asserted at import.
    if !filter.isEmpty, filter != Filter.color {
      cards.append(FITSHeader.Card(keyword: "FILTER", value: "'\(filter)'"))
    }
    if scenario.isColour { cards.append(FITSHeader.Card(keyword: "BAYERPAT", value: "'RGGB'")) }
    let image = AstroImage(
      width: Self.size, height: Self.size, planes: [pixels],
      metadata: ImageMetadata(rowOrder: .topDown))
    try FITSFile.create(image, keeping: FITSHeader(cards: cards), at: url)
    return url
  }

  /// A frame's start in the night of 2026-10-01 (UTC).
  static func dateObs(_ index: Int) -> String {
    // Six minutes apart: a 300 s exposure ends before the next frame starts.
    let minutes = 22 * 60 + 6 * index
    let (day, hour, minute) = (1 + minutes / (24 * 60), minutes / 60 % 24, minutes % 60)
    return String(format: "2026-10-%02dT%02d:%02d:00", day, hour, minute)
  }

  // MARK: - Pixels

  /// A light: sky, the seeded star field shifted by a small per-frame dither, and noise; a
  /// narrowband filter sees a dimmer sky and the same stars.
  private func light(seed: UInt64, filter: String) -> [Float] {
    let sky: Float = Filter.isNarrowband(filter) ? 0.02 : 0.06
    let (dx, dy) = (Float(seed % 3), Float((seed / 3) % 3))
    var random = Self.Random(seed: seed &+ 101)
    var pixels = [Float](repeating: sky, count: Self.size * Self.size)
    for star in Self.stars {
      let (cx, cy) = (star.x + dx, star.y + dy)
      let x0 = max(0, Int(cx) - 6)
      let x1 = min(Self.size - 1, Int(cx) + 6)
      let y0 = max(0, Int(cy) - 6)
      let y1 = min(Self.size - 1, Int(cy) + 6)
      for y in y0...y1 {
        for x in x0...x1 {
          let (ex, ey) = (Float(x) - cx, Float(y) - cy)
          pixels[y * Self.size + x] += star.flux * exp(-(ex * ex + ey * ey) / (2 * 1.6 * 1.6))
        }
      }
    }
    for index in pixels.indices { pixels[index] += 0.004 * random.signed() }
    if scenario.isColour { Self.mosaic(&pixels) }
    return pixels.map { min(max($0, 0), 1) }
  }

  /// A flat: a vignetted half-scale field.
  private func flat(seed: UInt64) -> [Float] {
    var random = Self.Random(seed: seed &+ 7)
    let centre = Float(Self.size) / 2
    return (0..<(Self.size * Self.size)).map { index in
      let (x, y) = (Float(index % Self.size) - centre, Float(index / Self.size) - centre)
      let vignette = 1 - 0.3 * (x * x + y * y) / (2 * centre * centre)
      return 0.5 * vignette + 0.002 * random.signed()
    }
  }

  private func uniform(_ level: Float, seed: UInt64) -> [Float] {
    var random = Self.Random(seed: seed &+ 13)
    return (0..<(Self.size * Self.size)).map { _ in level + 0.0005 * random.signed() }
  }

  /// An RGGB mosaic of a grey frame: green sites keep it, red and blue sites take 0.8 and 0.6.
  private static func mosaic(_ pixels: inout [Float]) {
    for index in pixels.indices {
      let (x, y) = (index % size, index / size)
      switch (y % 2, x % 2) {
      case (0, 0): pixels[index] *= 0.8
      case (1, 1): pixels[index] *= 0.6
      default: break
      }
    }
  }

  /// 60 stars from one seed: the same field in every frame of every scenario.
  private static let stars: [(x: Float, y: Float, flux: Float)] = {
    var random = Random(seed: 42)
    return (0..<60).map { _ in
      (
        x: 12 + random.unit() * Float(size - 24), y: 12 + random.unit() * Float(size - 24),
        flux: 0.1 + 0.8 * random.unit()
      )
    }
  }()

  /// A 64-bit linear congruential generator: the same numbers on every machine.
  struct Random {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }

    /// In [0, 1).
    mutating func unit() -> Float {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Float(state >> 40) / Float(1 << 24)
    }

    /// In [-1, 1).
    mutating func signed() -> Float { 2 * unit() - 1 }
  }
}
