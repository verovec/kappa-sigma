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
  private var closed = false

  /// Each plane's noise of `head` when known; else measures `image` and calls `done` once it is.
  ///
  /// Once `close`d, nothing is measured any more.
  func sigma(of head: String, image: AstroImage, then done: @escaping () -> Void) -> [Double]? {
    guard !closed else { return nil }
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

  /// Drops the measurement under way and measures nothing more (the workspace retired).
  func close() {
    closed = true
    stop()
  }

  /// Drops the measurement under way (another head).
  private func stop() {
    task?.cancel()
    task = nil
    measuring = nil
  }

  /// StackKit's starlet noise of each plane, the median tile σ of its finest scale.
  ///
  /// Nil once cancelled. One plane at a time on purpose (about 1 s each on a full frame): a
  /// cancel lands between planes, and one plane's decomposition buffers exist at once instead of
  /// three — the suggestion appears after ~3 s on a colour head rather than ~1 s.
  @concurrent
  private nonisolated static func measure(_ planes: [[Float]], width: Int, height: Int) async
    -> [Double]?
  {
    var sigma: [Double] = []
    for plane in planes {
      guard !Task.isCancelled else { return nil }
      sigma.append(StarletDenoiser.measure(plane, width: width, height: height))
    }
    return Task.isCancelled ? nil : sigma
  }
}
