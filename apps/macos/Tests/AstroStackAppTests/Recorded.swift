import Synchronization

/// Values a `@Sendable` fake saw, in order.
final class Recorded<Value: Sendable>: Sendable {
  private let values = Mutex<[Value]>([])

  func append(_ value: Value) { values.withLock { $0.append(value) } }

  var all: [Value] { values.withLock { $0 } }
}
