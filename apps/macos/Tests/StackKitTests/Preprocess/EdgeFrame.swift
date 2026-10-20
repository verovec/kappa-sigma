import Foundation
import StackKit

/// The synthetic frames of the legacy `edgecrop_test.go`: a sky at 0.245 whose per-pixel noise is
/// a few parts in 100 000, so the "invisible" 0.2% edge excess is tens of sigma. Getting that
/// ratio right is the whole point — a test with loud noise would pass with any threshold.
struct EdgeFrame {
  static let sky = 0.245
  /// Per-pixel sigma.
  static let noise = 2e-5
  /// Peak edge excess: 25 sigma per pixel, ~250× the line-to-line scatter.
  static let skirt = 5e-4

  let width: Int
  let height: Int
  var pixels: [Float]

  /// A flat, noisy, featureless sky — the thing every other case is a perturbation of.
  init(width: Int = 2400, height: Int = 900) {
    self.width = width
    self.height = height
    var rng = SeededGaussian(seed: 7)
    pixels = (0..<width * height).map { _ in Float(Self.sky + rng.next() * Self.noise) }
  }

  /// The artefact a drifting session leaves on its own stack: a dead wedge tapering with y and,
  /// beside it, a band both brighter and noisier than the interior (fewer frames reached it).
  mutating func addDriftEdge(wedge: Int, skirt skirtWidth: Int) {
    var rng = SeededGaussian(seed: 11)
    let peak = Double(skirtWidth) / 4
    for y in 0..<height {
      let deadTo = Int(Double(wedge) * (1 - Double(y) / Double(height)) * 1.4)
      for x in 0..<min(width, max(deadTo, skirtWidth)) {
        if x < deadTo {
          pixels[y * width + x] = 0
          continue
        }
        let distance = (Double(x) - peak) / (Double(skirtWidth) / 5.7)
        let shallow = exp(-0.5 * distance * distance)
        let extra = rng.next() * Self.noise * 7 * shallow
        pixels[y * width + x] += Float(Self.skirt * shallow + extra)
      }
    }
  }

  /// Adds `value(x, y)` to every pixel.
  mutating func add(_ value: (Double, Double) -> Double) {
    for y in 0..<height {
      for x in 0..<width { pixels[y * width + x] += Float(value(Double(x), Double(y))) }
    }
  }

  /// A nebula running off the left edge: bright there, same noise as the rest of the stack.
  mutating func addEdgeObject() {
    let middle = Double(height / 2)
    add { x, y in
      let (dx, dy) = (x / 260, (y - middle) / 400)
      return 0.06 * exp(-0.5 * (dx * dx + dy * dy))
    }
  }

  /// The measurement on this frame as one plane.
  func measure() -> (rect: EdgeRect, capped: Bool) {
    EdgeTrim.measure([pixels], width: width, height: height)
  }

  /// The kept rectangle as a new frame (the in-memory `cropFITS`).
  func cropped(to rect: EdgeRect) -> Self {
    let kept = (rect.y0..<rect.y1).flatMap { row in
      pixels[(row * width + rect.x0)..<(row * width + rect.x1)]
    }
    return Self(width: rect.width, height: rect.height, pixels: kept)
  }

  private init(width: Int, height: Int, pixels: [Float]) {
    self.width = width
    self.height = height
    self.pixels = pixels
  }
}
