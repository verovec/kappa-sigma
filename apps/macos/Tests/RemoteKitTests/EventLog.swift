import RemoteKit
import Synchronization

/// Collects the progress events a client reports, from any thread.
final class EventLog: Sendable {
  private let events = Mutex<[S3Progress]>([])

  func append(_ event: S3Progress) { events.withLock { $0.append(event) } }

  var all: [S3Progress] { events.withLock { $0 } }

  /// The attempt numbers of the retry events.
  var retries: [Int] {
    all.compactMap { if case .retrying(let attempt, _) = $0 { attempt } else { nil } }
  }

  /// The byte counts of the transfer events.
  var transferred: [Int64] {
    all.compactMap { if case .transferred(let bytes, _) = $0 { bytes } else { nil } }
  }
}

/// A thread-safe call counter: `next()` returns 0, 1, 2…
final class Counter: Sendable {
  private let value = Mutex(0)

  func next() -> Int {
    value.withLock { current in
      defer { current += 1 }
      return current
    }
  }
}
