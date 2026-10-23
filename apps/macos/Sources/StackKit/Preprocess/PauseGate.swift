internal import Synchronization

/// A one-shot, cooperative pause of one run (card 0097, the legacy `pauseGate`).
///
/// `request()` sets it; the run reads it after each lane and stops there. A lane is never
/// interrupted — Siril has no checkpoint inside a step.
package final class PauseGate: Sendable {
  private let flag = Atomic<Bool>(false)

  /// A gate not yet requested.
  package init() {}

  /// Asks the run to pause after the lane it is in.
  package func request() {
    flag.store(true, ordering: .sequentiallyConsistent)
  }

  /// Pause was asked.
  package var isRequested: Bool { flag.load(ordering: .sequentiallyConsistent) }
}
