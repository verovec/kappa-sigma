internal import ImageKit
internal import StackKit

/// The noise of the Studio's head, measured once per head off the main actor.
///
/// What the denoise's suggestion reads (card 0115); the process itself never measures (R2).
final class HeadNoise {
  /// The last head measured (its output file, `""` for the original) and its noise σ.
  private(set) var measured: (head: String, sigma: Double)?
  private var measuring: String?
  private var task: Task<Void, Never>?

  /// The noise of `head` when known; else measures `image` and calls `done` once it is.
  func sigma(of head: String, image: AstroImage, then done: @escaping () -> Void) -> Double? {
    if let measured, measured.head == head { return measured.sigma }
    guard measuring != head, let plane = image.planes.first else { return nil }
    measuring = head
    task?.cancel()
    let (width, height) = (image.width, image.height)
    task = Task { [weak self] in
      let sigma = await Self.measure(plane, width: width, height: height)
      guard let self, !Task.isCancelled, self.measuring == head else { return }
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

  /// StackKit's starlet noise of plane 0, the median tile σ of its finest scale.
  @concurrent
  private nonisolated static func measure(_ plane: [Float], width: Int, height: Int) async
    -> Double
  {
    StarletDenoiser.measure(plane, width: width, height: height)
  }
}
