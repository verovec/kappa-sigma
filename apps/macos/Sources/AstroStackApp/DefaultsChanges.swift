package import Foundation

/// Following a setting kept in the user defaults from a view that shows it (card 0177): Settings
/// writes them from its own window, and nothing else tells the others.
package enum DefaultsChanges {
  /// Calls `reload` now, then once per element of `changes` (every defaults write in the app
  /// unless a test hands its own), until the sequence ends or the task is cancelled.
  package static func follow<Changes: AsyncSequence>(
    _ changes: Changes, reload: () -> Void
  ) async {
    reload()
    do {
      for try await _ in changes { reload() }
    } catch {
      // A sequence that fails ends the following; the last value read stays shown.
    }
  }

  /// Every defaults write of this process.
  package static var live: NotificationCenter.Notifications {
    NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification)
  }
}
