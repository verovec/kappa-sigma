internal import ImageKit
internal import StackKit

/// The noise of the Studio's head, measured once per head off the main actor.
///
/// What the denoise's suggestion reads (card 0115); the process itself never measures (R2).
final class HeadNoise {
  /// The last head measured (its output file, `""` for the original) and each plane's noise σ.
  private(set) var measured: (head: String, sigma: [Double])?
  private var measuring: String?
  private var task: Task<Void, Never>?

  /// Each plane's noise of `head` when known; else measures `image` and calls `done` once it is.
  func sigma(of head: String, image: AstroImage, then done: @escaping () -> Void) -> [Double]? {
    if let measured, measured.head == head {
      // Back on a head already measured: a measurement of another one is no longer wanted.
      stop()
      return measured.sigma
    }
    guard measuring != head else { return nil }
    stop()
    measuring = head
    let (planes, width, height) = (image.planes, image.width, image.height)
    task = Task { [weak self] in
      let sigma = await Self.measure(planes, width: width, height: height)
      guard let self, let sigma, self.measuring == head else { return }
      self.measured = (head, sigma)
      self.measuring = nil
      done()
    }
    return nil
  }

  /// Waits for the measurement under way, if any (tests; no sleeps).
  func settle() async {
    await task?.value
  }

  /// Drops the measurement under way (another head, or the workspace retired).
  func stop() {
    task?.cancel()
    task = nil
    measuring = nil
  }

  /// StackKit's starlet noise of each plane, the median tile σ of its finest scale, the planes
  /// measured side by side; nil once cancelled (each plane is about a second on a full frame).
  @concurrent
  private nonisolated static func measure(_ planes: [[Float]], width: Int, height: Int) async
    -> [Double]?
  {
    let sigma = await withTaskGroup(of: (Int, Double?).self) { group in
      for (index, plane) in planes.enumerated() {
        group.addTask {
          guard !Task.isCancelled else { return (index, nil) }
          return (index, StarletDenoiser.measure(plane, width: width, height: height))
        }
      }
      var sigma = [Double?](repeating: nil, count: planes.count)
      for await (index, value) in group { sigma[index] = value }
      return sigma
    }
    guard !Task.isCancelled else { return nil }
    let measured = sigma.compactMap(\.self)
    return measured.count == planes.count ? measured : nil
  }
}
