internal import Foundation
package import ProjectKit
internal import StackKit

// MARK: - The remote sources of the Données stage (card 0169)

/// What the Données stage knows of one remote source: what its last successful scan counted, and
/// why the last scan failed if it did.
package struct RemoteSourceState: Equatable, Sendable {
  /// The source's virtual path (`s3://bucket/prefix`).
  package var path: String
  /// The lights the last successful scan found, `nil` when none ever succeeded in this window.
  package var lights: Int?
  /// Why the last scan failed, `nil` when the last one answered.
  package var failure: UserFacingError?
  /// This prefix is being read now (card 0182): the row says so beside its last count.
  ///
  /// Derived by `remoteState(of:)` from the scan in flight, never stored.
  package var isScanning: Bool

  /// A state for `path`.
  package init(
    path: String, lights: Int? = nil, failure: UserFacingError? = nil, isScanning: Bool = false
  ) {
    self.path = path
    self.lights = lights
    self.failure = failure
    self.isScanning = isScanning
  }
}

extension ProjectWindowModel {
  /// The project's remote sources (card 0168), in the order they were imported.
  package var remoteSources: [ProjectSource] { sources.filter { $0.kind == .remoteNight } }

  /// What the Données stage knows of the remote source at `path`, and whether it is being read.
  package func remoteState(of path: String) -> RemoteSourceState? {
    let reading = isScanningRemote && scanningRemotePath == path
    guard var state = remoteStates[path] ?? (reading ? RemoteSourceState(path: path) : nil)
    else { return nil }
    state.isScanning = reading
    return state
  }

  /// Keeps what the Import sheet's own scan of `target` counted, so the stage shows the lights
  /// it measured rather than a bare row (card 0169).
  func adoptRemoteScan(_ plan: ImportPlan, of target: RemoteImportTarget) {
    remoteStates[target.path] = RemoteSourceState(
      path: target.path, lights: plan.inventory.frames.count { $0.type == .light })
  }

  /// Each bucket row is being read for its own count (card 0182): after the plan, never
  /// holding Run back — the plan itself reads the bucket nights (card 0190).
  package var isScanningRemote: Bool { remoteScanTask != nil }

  /// Scans the remote sources in a task of their own (card 0182).
  ///
  /// It replaces a scan of them in flight, so one writer of `remoteStates` at a time; nothing
  /// without a remote source.
  func startRemoteScan() {
    cancelRemoteScan()
    guard !remoteSources.isEmpty else { return }
    remoteScanTask = Task {
      await rescanRemoteSources()
      // A stopped scan leaves the task to whoever stopped it (`cancelRemoteScan`), who may
      // already have started the next one.
      guard !Task.isCancelled else { return }
      remoteScanTask = nil
      scanningRemotePath = nil
    }
  }

  /// Stops the scan of the buckets in flight; each row keeps its last count and failure.
  func cancelRemoteScan() {
    remoteScanTask?.cancel()
    remoteScanTask = nil
    scanningRemotePath = nil
  }

  /// Scans every remote source through the connection it was imported with, one after another.
  ///
  /// A failure stays on its own row: the counts the last scan answered are kept, because an
  /// empty inventory would read as « this prefix holds no capture », which nothing measured (R2).
  func rescanRemoteSources() async {
    guard let planning = services(store()).remotePlanning else { return }
    for source in remoteSources {
      // Stopped before or between reads: nothing more is written, not even « Scanning… ».
      guard !Task.isCancelled else { return }
      guard let target = RemoteImportTarget(source: source) else {
        update(source.path) { $0.failure = .remoteImport(.connectionMissing) }
        continue
      }
      scanningRemotePath = source.path
      do {
        let plan = try await planning(target, ImportRequest(paths: [target.path])) { _ in }
        guard !Task.isCancelled else { return }
        update(source.path) {
          $0.lights = plan.inventory.frames.count { $0.type == .light }
          $0.failure = nil
        }
      } catch is CancellationError {
        // Ours, or the planner's own: the prefixes after it wait for the next Rescan.
        return
      } catch {
        guard !Task.isCancelled else { return }
        update(source.path) { $0.failure = UserFacingError(error) }
      }
    }
  }

  /// Changes the state of `path`, keeping what the change leaves alone.
  private func update(_ path: String, _ change: (inout RemoteSourceState) -> Void) {
    var state = remoteStates[path] ?? RemoteSourceState(path: path)
    change(&state)
    remoteStates[path] = state
  }
}
