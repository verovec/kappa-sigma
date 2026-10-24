package import Foundation
internal import Observation

/// What an install card knows of its tool: missing, being looked for, found at a path, too old,
/// or installed but unable to run.
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
    /// On disk at this executable, but this Mac cannot launch it; `reason` says what to install,
    /// as the caller wrote it (card 0108).
    case unusable(path: URL, reason: String)
  }

  /// The tool's state as the card shows it.
  package private(set) var state: State
  private let check: @Sendable @concurrent () async -> State

  /// A card in `state` that re-checks with `locate` (the host-tool client's lookup), which runs
  /// off the main actor: it probes paths and runs `--version`.
  package convenience init(
    state: State = .missing, locate: @escaping @Sendable @concurrent () async -> URL?
  ) {
    self.init(state: state) { @concurrent in await locate().map(State.found) ?? .missing }
  }

  /// A card in `state` whose re-check reports a full state (an outdated install stays outdated).
  package init(state: State, check: @escaping @Sendable @concurrent () async -> State) {
    self.state = state
    self.check = check
  }

  /// Asks the locator once and shows its answer; a re-check while one runs does nothing, so an
  /// older answer never overwrites a newer one.
  package func recheck() async {
    guard state != .checking else { return }
    state = .checking
    state = await check()
  }

  /// Shows a verdict found elsewhere (the window's « Re-check tools »), unless a re-check of
  /// this card is running: its own answer lands last.
  package func show(_ verdict: State) {
    guard state != .checking else { return }
    state = verdict
  }
}
