package import Foundation
internal import Observation

/// What an install card knows of its tool: missing, being looked for, or found at a path.
///
/// The card never probes on its own: it shows the verdict it was given, and asks `locate` again
/// only on « Re-check ». A missing tool greys its process; nothing falls back (R2).
@MainActor
@Observable
package final class InstallCardModel {
  /// The tool's state.
  package enum State: Equatable, Sendable {
    /// Not found.
    case missing
    /// The locator is running.
    case checking
    /// Found at this executable.
    case found(URL)
    /// Installed, but this version is older than the one the app needs.
    case outdated(version: String)
  }

  /// The tool's state as the card shows it.
  package private(set) var state: State
  private let locate: @Sendable @concurrent () async -> URL?

  /// A card in `state` that re-checks with `locate` (the host-tool client's lookup), which runs
  /// off the main actor: it probes paths and runs `--version`.
  package init(state: State = .missing, locate: @escaping @Sendable @concurrent () async -> URL?) {
    self.state = state
    self.locate = locate
  }

  /// Asks the locator once and shows its answer; a re-check while one runs does nothing, so an
  /// older answer never overwrites a newer one.
  package func recheck() async {
    guard state != .checking else { return }
    state = .checking
    state = await locate().map(State.found) ?? .missing
  }
}
