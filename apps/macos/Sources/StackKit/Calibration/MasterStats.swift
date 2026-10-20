internal import Accelerate
internal import ImageKit

/// What a calibration master's pixels say (card 0071): measured, displayed, never acted on (R2).
///
/// Measured on the mean of the planes. Medians and MAD come from a regular grid of about
/// `sampleBudget` pixels (every pixel up to 4 × the budget) whose step is odd, so a CFA master is
/// sampled over all four Bayer phases; vignetting is measured on 2×2 block means (one Bayer
/// superpixel each: a corner patch never reads another colour than the centre); min, max,
/// clipped % and hot pixels count every pixel.
package struct MasterStats: Equatable, Sendable {
  package var type: MasterType
  package var median: Double
  /// 1.4826 × MAD: the noise σ of a Gaussian.
  package var madn: Double
  package var min: Double
  package var max: Double
  /// Medians of the four quadrants, in file rows: top-left, top-right, bottom-left, bottom-right.
  package var quadrantMedians: [Double]
  /// Flats only: (mean corner median ÷ centre median − 1) × 100 on 10 % patches of the 2×2
  /// block means; a healthy flat is negative (vignetting).
  package var vignettingPct: Double?
  /// Pixels at or above full scale, in %.
  package var clippedPct: Double
  /// Darks only: pixels above median + max(10 σ, 0.1 % of full scale) — the floor keeps a
  /// quantised master with MAD 0 from counting every pixel one step above its median.
  package var hotPixels: Int?
  /// Full scale: 1 for Siril's normalised float masters, 65535 for integer data.
  package var fullScale: Double
  package var pixelCount: Int

  /// The statistics of a `type` master of `planes`, each `width × height`.
  package init(
    type: MasterType, width: Int, height: Int, planes: [[Float]], sampleBudget: Int = 1_000_000
  ) {
    let count = width * height
    let plane =
      planes.isEmpty || planes.contains { $0.count != count } ? [] : Self.mean(planes)
    self.type = type
    pixelCount = plane.count
    min = plane.isEmpty ? 0 : Double(vDSP.minimum(plane))
    max = plane.isEmpty ? 0 : Double(vDSP.maximum(plane))
    fullScale = max <= 2 ? 1 : 65535
    let grid = Grid(
      width: plane.isEmpty ? 0 : width, height: plane.isEmpty ? 0 : height, plane: plane,
      budget: sampleBudget)
    let sample = grid.values(x: 0..<grid.width, y: 0..<grid.height)
    let center = Robust.median(sample)
    median = center
    madn = 1.4826 * Robust.median(sample.map { abs($0 - center) })
    quadrantMedians = grid.quadrants().map(Robust.median)
    let scale = Float(fullScale)
    clippedPct = Double(plane.count { $0 >= scale }) / Double(Swift.max(plane.count, 1)) * 100
    vignettingPct =
      type == .flat && !plane.isEmpty ? Self.vignetting(plane, width, height, sampleBudget) : nil
    let hot = Float(center + Swift.max(10 * madn, 0.001 * fullScale))
    hotPixels = type.isThermal ? plane.count { $0 > hot } : nil
  }

  private static func vignetting(_ plane: [Float], _ width: Int, _ height: Int, _ budget: Int)
    -> Double?
  {
    guard width >= 2, height >= 2 else { return nil }
    let binned = Pyramid(
      width: width, height: height, planes: [plane], smallestSide: Swift.max(width, height) / 2
    ).levels[1]
    return Grid(width: binned.width, height: binned.height, plane: binned.planes[0], budget: budget)
      .vignettingPct()
  }

  private static func mean(_ planes: [[Float]]) -> [Float] {
    guard let first = planes.first else { return [] }
    guard planes.count > 1 else { return first }
    var sum = first
    for plane in planes.dropFirst() { sum = vDSP.add(sum, plane) }
    return vDSP.divide(sum, Float(planes.count))
  }
}

/// A sampled view of one plane: a regular grid of every `step`-th pixel.
private struct Grid {
  var width: Int
  var height: Int
  var plane: [Float]
  var step: Int

  init(width: Int, height: Int, plane: [Float], budget: Int) {
    self.width = width
    self.height = height
    self.plane = plane
    let count = width * height
    let even = Int((Double(count) / Double(Swift.max(budget, 1))).squareRoot().rounded(.up))
    step = count <= 4 * budget ? 1 : even | 1
  }

  func values(x: Range<Int>, y: Range<Int>) -> [Double] {
    var out: [Double] = []
    out.reserveCapacity((x.count / step + 1) * (y.count / step + 1))
    for row in stride(from: y.lowerBound, to: y.upperBound, by: step) {
      for column in stride(from: x.lowerBound, to: x.upperBound, by: step) {
        out.append(Double(plane[row * width + column]))
      }
    }
    return out
  }

  func quadrants() -> [[Double]] {
    let (midX, midY) = (width / 2, height / 2)
    return [
      values(x: 0..<midX, y: 0..<midY), values(x: midX..<width, y: 0..<midY),
      values(x: 0..<midX, y: midY..<height), values(x: midX..<width, y: midY..<height),
    ]
  }

  /// Corners against centre on square patches a tenth of the short side.
  func vignettingPct() -> Double? {
    let side = Swift.max(Swift.min(width, height) / 10, 1)
    let (farX, farY) = (width - side, height - side)
    let corners = [(0, 0), (farX, 0), (0, farY), (farX, farY)].map { origin in
      Robust.median(values(x: origin.0..<origin.0 + side, y: origin.1..<origin.1 + side))
    }
    let (cx, cy) = ((width - side) / 2, (height - side) / 2)
    let centre = Robust.median(values(x: cx..<cx + side, y: cy..<cy + side))
    guard centre > 0 else { return nil }
    return (corners.reduce(0, +) / 4 / centre - 1) * 100
  }
}
