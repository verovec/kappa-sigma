internal import Accelerate

extension AstroImage {
  /// `self − other`, plane by plane (a background model from an image and its corrected version).
  package func subtracting(_ other: AstroImage) throws -> AstroImage {
    try combined(with: other) { vDSP.subtract($0, $1) }
  }

  /// `self ÷ other`, plane by plane; where the divisor is not positive the ratio means nothing,
  /// so the result is 1 there (no correction) rather than a spike.
  package func dividing(by other: AstroImage) throws -> AstroImage {
    try combined(with: other) { numerator, divisor in
      var ratio = vDSP.divide(
        numerator, vDSP.threshold(divisor, to: .leastNormalMagnitude, with: .clampToThreshold))
      // vDSP has no select: the few non-positive divisors are patched by hand.
      for index in divisor.indices where divisor[index] <= 0 { ratio[index] = 1 }
      return ratio
    }
  }

  private func combined(with other: AstroImage, _ operation: ([Float], [Float]) -> [Float]) throws
    -> AstroImage
  {
    guard other.width == width, other.height == height, other.planes.count == planes.count else {
      throw AstroImageError.shapeMismatch(width: width, height: height, planes: planes.count)
    }
    var combined: [[Float]] = []
    for (plane, otherPlane) in zip(planes, other.planes) {
      try Task.checkCancellation()
      combined.append(operation(plane, otherPlane))
    }
    return AstroImage(width: width, height: height, planes: combined, metadata: metadata)
  }
}
