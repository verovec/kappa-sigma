package import Foundation
internal import Synchronization

/// One run per target: the output folders held by running preprocessors, process-wide.
package enum TargetLock {
  private static let held = Mutex<Set<String>>([])

  /// Takes `folder`, or throws `targetBusy` when another run holds it.
  package static func acquire(_ folder: URL) throws {
    let key = folder.standardizedFileURL.path
    let taken = held.withLock { $0.insert(key).inserted }
    guard taken else { throw PreprocessError.targetBusy(key) }
  }

  /// True while a run holds `folder`.
  package static func isHeld(_ folder: URL) -> Bool {
    let key = folder.standardizedFileURL.path
    return held.withLock { $0.contains(key) }
  }

  /// Releases `folder`.
  package static func release(_ folder: URL) {
    let key = folder.standardizedFileURL.path
    _ = held.withLock { $0.remove(key) }
  }
}
