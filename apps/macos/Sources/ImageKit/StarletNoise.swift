/// The noise of the à-trous B3-spline starlet planes: what a threshold in σ of the image noise
/// becomes at each scale, for the stacking denoiser (StackKit) and the Studio's (ProcessKit).
package enum StarletNoise {
  /// The SNR band (in σ above the background) over which a pixel goes from denoised to kept by
  /// a starlet denoiser's protection (`noise/weighted.go`).
  package static let protection = (low: 5.0, high: 10.0)

  /// Per scale, the sigma of a detail plane of unit-variance white noise (`noise/starlet.go`).
  package static let whiteNoiseSigma = [0.8907, 0.2007, 0.0855, 0.0412, 0.0205, 0.0107]

  /// The white-noise detail sigma at scale j, halving per octave past the table.
  package static func scaleSigma(_ scale: Int) -> Double {
    let index = max(0, scale)
    guard index >= whiteNoiseSigma.count, let last = whiteNoiseSigma.last else {
      return whiteNoiseSigma[index]
    }
    return (whiteNoiseSigma.count...index).reduce(last) { value, _ in value * 0.5 }
  }
}
