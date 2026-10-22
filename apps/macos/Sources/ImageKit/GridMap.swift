/// A move of the pixel grid that keeps every pixel whole (card 0090): a crop, flips and quarter
/// turns, composed into one map.
///
/// In 1-based FITS pixel coordinates (the WCS's), an input pixel `p` lands at
/// `matrix · p + offset`, `matrix` a signed permutation; the same map drives the index copy and
/// the plate solution (`FITSHeader.moved(by:)`), so a star keeps its RA/Dec. Coordinates are the
/// stored ones: x along a row, y along the stored rows.
package struct GridMap: Equatable, Sendable, CustomStringConvertible {
  /// `[m11, m12, m21, m22]`: each row and column has one ±1.
  package let matrix: SIMD4<Int>
  /// Added after the matrix (1-based coordinates).
  package let offset: SIMD2<Int>
  /// The output's columns.
  package let width: Int
  /// The output's rows.
  package let height: Int

  /// The grid of `width` × `height` left as it is.
  package static func identity(width: Int, height: Int) -> Self {
    Self(matrix: [1, 0, 0, 1], offset: [0, 0], width: width, height: height)
  }

  /// `left`/`right` columns and the `first`/`last` stored rows removed (the result may be empty;
  /// the caller refuses that).
  package func cropped(left: Int, first: Int, right: Int, last: Int) -> Self {
    then([1, 0, 0, 1], [-left, -first], width - left - right, height - first - last)
  }

  /// Mirrored left–right.
  package func flippedX() -> Self {
    then([-1, 0, 0, 1], [width + 1, 0], width, height)
  }

  /// The stored rows in reverse order.
  package func flippedY() -> Self {
    then([1, 0, 0, -1], [0, height + 1], width, height)
  }

  /// Turned a quarter: (x, y) → (height + 1 − y, x).
  ///
  /// Input row 1 becomes the last column; with rows shown top-down, that is clockwise on screen.
  package func quarterTurned() -> Self {
    then([0, -1, 1, 0], [height + 1, 0], height, width)
  }

  /// Where input pixel `input` (0-based) lands (0-based; outside the output when cropped away).
  package func output(ofInput input: SIMD2<Int>) -> SIMD2<Int> {
    apply(matrix, input &+ 1) &+ offset &- 1
  }

  /// The input pixel (0-based) that output pixel `output` (0-based) comes from.
  package func input(ofOutput output: SIMD2<Int>) -> SIMD2<Int> {
    apply(inverse, output &+ 1 &- offset) &- 1
  }

  /// The inverse matrix (the transpose of a signed permutation).
  package var inverse: SIMD4<Int> { [matrix[0], matrix[2], matrix[1], matrix[3]] }

  package var description: String {
    "GridMap(\(matrix), \(offset), \(width)×\(height))"
  }

  /// `step` after this map: `step · (matrix · p + offset) + shift`.
  private func then(_ step: SIMD4<Int>, _ shift: SIMD2<Int>, _ width: Int, _ height: Int) -> Self {
    let product = SIMD4(
      step[0] * matrix[0] + step[1] * matrix[2], step[0] * matrix[1] + step[1] * matrix[3],
      step[2] * matrix[0] + step[3] * matrix[2], step[2] * matrix[1] + step[3] * matrix[3])
    return Self(
      matrix: product, offset: apply(step, offset) &+ shift, width: width, height: height)
  }

  private func apply(_ matrix: SIMD4<Int>, _ point: SIMD2<Int>) -> SIMD2<Int> {
    SIMD2(
      matrix[0] * point.x + matrix[1] * point.y, matrix[2] * point.x + matrix[3] * point.y)
  }
}
