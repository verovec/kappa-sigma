internal import Synchronization

/// A body that runs at most once, whichever thread calls first; later and concurrent calls
/// return at once (after the first one finished).
///
/// Teardowns that close file descriptors need it: two overlapping closes of the same number can
/// close a descriptor another component was handed in between.
package final class RunOnce: Sendable {
  private let body: Mutex<(@Sendable () -> Void)?>

  /// A guard around `body`.
  package init(_ body: @escaping @Sendable () -> Void) {
    self.body = Mutex(body)
  }

  /// Runs the body if no call has yet; holds the lock while it runs, so a concurrent caller
  /// returns only once the teardown is complete.
  package func run() {
    body.withLock { pending in
      pending?()
      pending = nil
    }
  }

  /// Whether the body has run.
  package var hasRun: Bool { body.withLock { $0 == nil } }
}
