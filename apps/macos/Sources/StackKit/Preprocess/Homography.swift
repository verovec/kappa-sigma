internal import Foundation

/// The 3×3 row-major registration homographies of a `.seq` (`grade/homography.go`): re-referencing
/// onto a chosen frame, the footprint overlap with the reference canvas, the field rotation.
package enum Homography {
  package static let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

  /// ref⁻¹ · h: the frame re-referenced onto the frame whose homography is `reference`; nil when
  /// `reference` is singular (an unregistered frame).
  package static func relative(_ reference: [Double], _ frame: [Double]) -> [Double]? {
    invert(reference).map { multiply($0, frame) }
  }

  /// The fraction of the w×h canvas covered by the bounding box of the transformed frame.
  package static func footprintOverlap(_ relative: [Double], width: Double, height: Double) -> Double {
    guard width > 0, height > 0 else { return 0 }
    var (minX, minY, maxX, maxY) = (Double.infinity, Double.infinity, -Double.infinity, -Double.infinity)
    for (x, y) in [(0, 0), (width, 0), (0, height), (width, height)] {
      guard let point = apply(relative, x: x, y: y) else { return 0 }
      (minX, maxX) = (min(minX, point.x), max(maxX, point.x))
      (minY, maxY) = (min(minY, point.y), max(maxY, point.y))
    }
    let spanX = min(maxX, width) - max(minX, 0)
    let spanY = min(maxY, height) - max(minY, 0)
    guard spanX > 0, spanY > 0 else { return 0 }
    return spanX * spanY / (width * height)
  }

  /// The field rotation in degrees, (−180, 180].
  package static func rotationDegrees(_ relative: [Double]) -> Double {
    let degrees = atan2(relative[3], relative[0]) * 180 / .pi
    return degrees <= -180 ? degrees + 360 : degrees
  }

  /// The inverse through the adjugate; nil when |det| < 1e-12.
  static func invert(_ m: [Double]) -> [Double]? {
    let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    guard abs(det) >= 1e-12 else { return nil }
    let adjugate = [
      e * i - f * h, c * h - b * i, b * f - c * e,
      f * g - d * i, a * i - c * g, c * d - a * f,
      d * h - e * g, b * g - a * h, a * e - b * d,
    ]
    return adjugate.map { $0 / det }
  }

  /// a · b.
  static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
    (0..<9).map { index in
      let (row, column) = (index / 3, index % 3)
      return a[row * 3] * b[column] + a[row * 3 + 1] * b[3 + column] + a[row * 3 + 2] * b[6 + column]
    }
  }

  /// (x, y) through the projective divide; nil at a degenerate horizon.
  package static func apply(_ m: [Double], x: Double, y: Double) -> (x: Double, y: Double)? {
    let w = m[6] * x + m[7] * y + m[8]
    guard abs(w) >= 1e-12 else { return nil }
    return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w)
  }
}
