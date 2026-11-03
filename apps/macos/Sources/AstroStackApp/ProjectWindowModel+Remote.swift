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

  /// A state for `path`.
  package init(path: String, lights: Int? = nil, failure: UserFacingError? = nil) {
    self.path = path
    self.lights = lights
    self.failure = failure
  }
}

extension ProjectWindowModel {
  /// The project's remote sources (card 0168), in the order they were imported.
  package var remoteSources: [ProjectSource] { sources.filter { $0.kind == .remoteNight } }

  /// What the Données stage knows of the remote source at `path`.
  package func remoteState(of path: String) -> RemoteSourceState? { remoteStates[path] }

  /// Keeps what the Import sheet's own scan of `target` counted, so the stage shows the lights
  /// it measured rather than a bare row (card 0169).
  func adoptRemoteScan(_ plan: ImportPlan, of target: RemoteImportTarget) {
    remoteStates[target.path] = RemoteSourceState(
      path: target.path, lights: plan.inventory.frames.count { $0.type == .light })
  }

  /// Scans every remote source through the connection it was imported with, one after another.
  ///
  /// A failure stays on its own row: the counts the last scan answered are kept, because an
  /// empty inventory would read as « this prefix holds no capture », which nothing measured (R2).
  func rescanRemoteSources() async {
    guard let planning = services(store()).remotePlanning else { return }
    for source in remoteSources {
      guard let target = Self.target(of: source) else {
        update(source.path) { $0.failure = .remoteImport(.connectionMissing) }
        continue
      }
      do {
        let plan = try await planning(target, ImportRequest(paths: [target.path])) { _ in }
        guard !Task.isCancelled else { return }
        update(source.path) {
          $0.lights = plan.inventory.frames.count { $0.type == .light }
          $0.failure = nil
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        update(source.path) { $0.failure = UserFacingError(error) }
      }
    }
  }

  /// The target a remote source row names (card 0168 stores all three); `nil` when the row was
  /// written by a build that did not, or its connection id is not one.
  static func target(of source: ProjectSource) -> RemoteImportTarget? {
    guard let bucket = source.bucket, let prefix = source.prefix,
      let connection = source.connectionID.flatMap(UUID.init(uuidString:))
    else { return nil }
    return RemoteImportTarget(connectionID: connection, bucket: bucket, prefix: prefix)
  }

  /// Changes the state of `path`, keeping what the change leaves alone.
  private func update(_ path: String, _ change: (inout RemoteSourceState) -> Void) {
    var state = remoteStates[path] ?? RemoteSourceState(path: path)
    change(&state)
    remoteStates[path] = state
  }
}
