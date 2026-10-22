internal import Synchronization

/// One lane's pause at a breakpoint (cards 0069, 0096): the run waits on it, the user's answer
/// resumes it, cancelling the run releases it.
///
/// The gate travels inside the event that raised the pause, so whoever consumes the stream can
/// answer without holding the `Preprocessor`. It answers once: a second `resume`, a second
/// awaiter, or an answer after cancellation is ignored.
package final class ReviewGate<Answer: Sendable>: Sendable {
  private enum State {
    case idle
    case waiting(CheckedContinuation<Answer, any Error>)
    case answered(Answer)
    case closed
  }

  /// The lane (filter) being reviewed.
  package let lane: String
  private let state = Mutex<State>(.idle)

  /// A gate for `lane`.
  package init(lane: String) {
    self.lane = lane
  }

  /// The run is waiting on it now.
  package var isWaiting: Bool {
    state.withLock { state in
      if case .waiting = state { return true }
      return false
    }
  }

  /// Resumes the run with `answer`.
  package func resume(_ answer: Answer) {
    let waiting: CheckedContinuation<Answer, any Error>? = state.withLock { state in
      switch state {
      case .idle:
        state = .answered(answer)
        return nil
      case .waiting(let continuation):
        state = .closed
        return continuation
      case .answered, .closed:
        return nil
      }
    }
    waiting?.resume(returning: answer)
  }

  /// The user's answer, once given.
  ///
  /// Throws `CancellationError` when the run is cancelled first. The run awaits it; a test's
  /// fake run may too.
  package func answer() async throws -> Answer {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let early: Result<Answer, any Error>? = state.withLock { state in
          switch state {
          case .idle:
            state = .waiting(continuation)
            return nil
          case .answered(let answer):
            state = .closed
            return .success(answer)
          case .waiting:
            // A second awaiter is refused; the first keeps its wait.
            return .failure(CancellationError())
          case .closed:
            // Cancelled before the wait began: never a hang.
            return .failure(CancellationError())
          }
        }
        if let early { continuation.resume(with: early) }
      }
    } onCancel: {
      cancel()
    }
  }

  /// Releases a waiting run with `CancellationError`; a later answer is ignored.
  private func cancel() {
    let waiting: CheckedContinuation<Answer, any Error>? = state.withLock { state in
      guard case .waiting(let continuation) = state else {
        state = .closed
        return nil
      }
      state = .closed
      return continuation
    }
    waiting?.resume(throwing: CancellationError())
  }
}

extension ReviewGate: Equatable {
  /// Identity: the event that carries a gate is equal to itself only.
  package static func == (lhs: ReviewGate, rhs: ReviewGate) -> Bool {
    lhs === rhs
  }
}

/// The frame review's gate (card 0069): answered with the keep / reject decision.
package typealias FrameReviewGate = ReviewGate<FrameDecision>

/// The reference pin's gate (card 0096): answered with the pinned `FrameGrade.index`, or nil to
/// keep the elected frame.
package typealias ReferencePinGate = ReviewGate<Int?>

extension ReviewGate where Answer == FrameDecision {
  /// The user's decision, once given (`answer()`).
  package func decision() async throws -> FrameDecision {
    try await answer()
  }
}
