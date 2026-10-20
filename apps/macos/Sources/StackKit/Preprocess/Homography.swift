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
  package static func footprintOverlap(_ relative: [Double], width: Double, height: Double)
    -> Double
  {
    guard width > 0, height > 0 else { return 0 }
    var (minX, minY, maxX, maxY) = (
      Double.infinity, Double.infinity, -Double.infinity, -Double.infinity
    )
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
  static func invert(_ matrix: [Double]) -> [Double]? {
    let (m00, m01, m02) = (matrix[0], matrix[1], matrix[2])
    let (m10, m11, m12) = (matrix[3], matrix[4], matrix[5])
    let (m20, m21, m22) = (matrix[6], matrix[7], matrix[8])
    let det =
      m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02
      * (m10 * m21 - m11 * m20)
    guard abs(det) >= 1e-12 else { return nil }
    let adjugate = [
      m11 * m22 - m12 * m21, m02 * m21 - m01 * m22, m01 * m12 - m02 * m11,
      m12 * m20 - m10 * m22, m00 * m22 - m02 * m20, m02 * m10 - m00 * m12,
      m10 * m21 - m11 * m20, m01 * m20 - m00 * m21, m00 * m11 - m01 * m10,
    ]
    return adjugate.map { $0 / det }
  }

  /// lhs · rhs.
  static func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    (0..<9).map { index in
      let (row, column) = (index / 3, index % 3)
      return lhs[row * 3] * rhs[column] + lhs[row * 3 + 1] * rhs[3 + column] + lhs[row * 3 + 2]
        * rhs[6 + column]
    }
  }

  /// (x, y) through the projective divide; nil at a degenerate horizon.
  package static func apply(_ matrix: [Double], x: Double, y: Double) -> (x: Double, y: Double)? {
    let w = matrix[6] * x + matrix[7] * y + matrix[8]
    guard abs(w) >= 1e-12 else { return nil }
    return (
      (matrix[0] * x + matrix[1] * y + matrix[2]) / w,
      (matrix[3] * x + matrix[4] * y + matrix[5]) / w
    )
  }
}
