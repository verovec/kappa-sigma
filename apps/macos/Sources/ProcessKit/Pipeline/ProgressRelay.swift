internal import Synchronization

/// Collects a batch tool's progress values, reported from the tool's own task.
final class ProgressRelay: Sendable {
  private let storage = Mutex<[Double]>([])

  /// Records `value`.
  func append(_ value: Double) {
    storage.withLock { $0.append(value) }
  }

  /// Every value recorded, in order.
  var values: [Double] { storage.withLock { $0 } }
}
