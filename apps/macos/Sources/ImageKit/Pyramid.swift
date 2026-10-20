internal import Accelerate

/// Mip levels of an image for display: each level halves the previous by 2×2 block means.
///
/// Block means, never stride sampling: a sampled level keeps full-resolution noise and a viewer
/// zoomed out would show a noise level the image does not have (E04 analysis). An odd last row
/// or column is dropped (sizes round down).
package struct Pyramid: Sendable {
  /// One level.
  package struct Level: Sendable {
    /// Width in pixels.
    package let width: Int
    /// Height in pixels.
    package let height: Int
    /// The planes at this level.
    package let planes: [[Float]]
  }

  /// Level 0 is the image itself.
  package let levels: [Level]

  /// Builds the levels until the longer side is at most `smallestSide`.
  ///
  /// Every plane must hold `width * height` values: a mismatch is a caller bug (vDSP would read
  /// past the buffer), so it stops the process instead of being guessed around.
  package init(width: Int, height: Int, planes: [[Float]], smallestSide: Int = 512) {
    precondition(
      planes.allSatisfy { $0.count == width * height }, "Pyramid: plane size ≠ width × height")
    var levels = [Level(width: width, height: height, planes: planes)]
    while let last = levels.last, max(last.width, last.height) > smallestSide,
      last.width >= 2, last.height >= 2
    {
      levels.append(Self.halve(last))
    }
    self.levels = levels
  }

  /// Builds off the caller's actor (CPU-bound: never on the main actor).
  @concurrent
  package static func build(
    width: Int, height: Int, planes: [[Float]], smallestSide: Int = 512
  ) async -> Self {
    Self(width: width, height: height, planes: planes, smallestSide: smallestSide)
  }

  /// 2×2 block means of every plane, with vDSP: rows pairwise, then columns pairwise.
  private static func halve(_ level: Level) -> Level {
    let width = level.width / 2
    let height = level.height / 2
    let planes = level.planes.map { plane in
      [Float](unsafeUninitializedCapacity: width * height) { out, initialized in
        var rowSum = [Float](repeating: 0, count: level.width)
        plane.withUnsafeBufferPointer { src in
          guard let source = src.baseAddress, let target = out.baseAddress else { return }
          rowSum.withUnsafeMutableBufferPointer { sum in
            guard let rows = sum.baseAddress else { return }
            for y in 0..<height {
              let top = source + 2 * y * level.width
              vDSP_vadd(top, 1, top + level.width, 1, rows, 1, vDSP_Length(level.width))
              let dest = target + y * width
              vDSP_vadd(rows, 2, rows + 1, 2, dest, 1, vDSP_Length(width))
              var quarter: Float = 0.25
              vDSP_vsmul(dest, 1, &quarter, dest, 1, vDSP_Length(width))
            }
          }
        }
        initialized = width * height
      }
    }
    return Level(width: width, height: height, planes: planes)
  }
}
