internal import Synchronization

/// One lane's pause at the frame-review breakpoint (card 0069): the run waits on it, the user's
/// decision resumes it, cancelling the run releases it.
///
/// The gate travels inside the `PreprocessEvent.frames` event, so whoever consumes the stream can
/// answer without holding the `Preprocessor`. It answers once: a second `resume` or an answer
/// after cancellation is ignored.
package final class FrameReviewGate: Sendable {
  private enum State {
    case idle
    case waiting(CheckedContinuation<FrameDecision, any Error>)
    case answered(FrameDecision)
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

  /// Resumes the run with `decision`.
  package func resume(_ decision: FrameDecision) {
    let waiting: CheckedContinuation<FrameDecision, any Error>? = state.withLock { state in
      switch state {
      case .idle:
        state = .answered(decision)
        return nil
      case .waiting(let continuation):
        state = .closed
        return continuation
      case .answered, .closed:
        return nil
      }
    }
    waiting?.resume(returning: decision)
  }

  /// The user's decision, once given.
  ///
  /// Throws `CancellationError` when the run is cancelled first. The run awaits it; a test's
  /// fake run may too.
  package func decision() async throws -> FrameDecision {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let early: Result<FrameDecision, any Error>? = state.withLock { state in
          switch state {
          case .idle:
            state = .waiting(continuation)
            return nil
          case .answered(let decision):
            state = .closed
            return .success(decision)
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
    let waiting: CheckedContinuation<FrameDecision, any Error>? = state.withLock { state in
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

extension FrameReviewGate: Equatable {
  /// Identity: the event that carries a gate is equal to itself only.
  package static func == (lhs: FrameReviewGate, rhs: FrameReviewGate) -> Bool {
    lhs === rhs
  }
}
