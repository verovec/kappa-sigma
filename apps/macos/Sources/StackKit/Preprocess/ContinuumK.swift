package import Foundation
internal import ImageKit

/// The continuum scale k of an emission layer (`lineContinuumSubtract`): excess = line − k·ref
/// cancels stars and broadband structure, leaving the true emission. Measured and recorded on
/// the bundle (R2: a value shown); the subtraction itself is the Studio's (0051).
///
/// k is the median line/ref ratio over the continuum-bright reference pixels (P85 < ref < P99.9,
/// at most 2 M strided samples). References: Hα and [SII] take R then L, [OIII] G, B then L, as
/// the legacy engine did; past those, a one-shot-colour base lends its red plane (Hα, [SII]) or
/// its green one ([OIII]), which the legacy list lacked and a mixed OSC capture needs.
package enum ContinuumK {
  /// A fitted scale and the layer it was fitted against.
  package struct Fit: Equatable, Sendable {
    package var k: Double
    package var reference: String
  }

  static let selection = (low: 85.0, high: 99.9)
  static let minimumSamples = 10_000

  /// Broadband filters by line, in order, then the colour plane to fall back on.
  static func references(of line: String) -> (filters: [String], colourPlane: Int)? {
    switch Filter.token(line) {
    case .hydrogenAlpha, .sulfurII: (["R", "L"], 0)
    case .oxygenIII: (["G", "B", "L"], 1)
    default: nil
    }
  }

  /// The fit of `line` among `layers` (filter → FITS), or why there is none.
  package static func measure(line: String, layers: [String: URL]) throws -> (
    fit: Fit?, reason: String?
  ) {
    guard let lineURL = layers[line], let (filters, colourPlane) = references(of: line) else {
      return (nil, "\(line) is not an emission line with a continuum reference")
    }
    let colour = layers.keys.sorted().first { Filter.isColor($0) }
    guard let reference = filters.first(where: { layers[$0] != nil }) ?? colour,
      let referenceURL = layers[reference]
    else {
      return (nil, "no broadband channel (\(filters.joined(separator: "/"))) to estimate the continuum from")
    }
    let lineImage = try FITSFile.read(at: lineURL).image()
    let referenceImage = try FITSFile.read(at: referenceURL).image()
    let plane = filters.contains(reference) ? 0 : colourPlane
    guard lineImage.width == referenceImage.width, lineImage.height == referenceImage.height,
      plane < referenceImage.planes.count
    else {
      return (nil, "\(line) \(lineImage.width)×\(lineImage.height) vs \(reference) "
        + "\(referenceImage.width)×\(referenceImage.height) — masters not co-registered")
    }
    switch scale(line: lineImage.planes[0], reference: referenceImage.planes[plane]) {
    case .success(let k): return (Fit(k: k, reference: reference), nil)
    case .failure(let reason): return (nil, "\(line)/\(reference): \(reason.text)")
    }
  }

  /// Why no scale could be fitted.
  struct Refusal: Error {
    var text: String
  }

  /// The median line/ref ratio over the continuum-bright reference pixels.
  static func scale(line: [Float], reference: [Float]) -> Result<Double, Refusal> {
    let sample = PhotomStats.subsample(reference, limit: 200_000)
    let low = PhotomStats.percentile(sample, selection.low)
    let high = PhotomStats.percentile(sample, selection.high)
    guard low > 1e-6, high > low else {
      return .failure(Refusal(text: "reference too dark/flat to calibrate the continuum "
        + "(P85=\(String(format: "%.2g", low)))"))
    }
    let stride = reference.count / 2_000_000 + 1
    var ratios: [Float] = []
    for index in Swift.stride(from: 0, to: reference.count, by: stride) {
      let value = reference[index]
      if Double(value) > low && Double(value) < high { ratios.append(line[index] / value) }
    }
    guard ratios.count >= minimumSamples else {
      return .failure(Refusal(text: "only \(ratios.count) continuum-bright pixels — cannot fit a stable scale"))
    }
    let k = PhotomStats.percentile(ratios, 50)
    guard k > 0, k.isFinite else {
      return .failure(Refusal(text: "degenerate continuum scale (\(String(format: "%.3g", k)))"))
    }
    return .success(k)
  }
}
