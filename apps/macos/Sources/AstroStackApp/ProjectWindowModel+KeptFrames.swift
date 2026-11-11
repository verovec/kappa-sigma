package import Foundation
internal import ProjectKit
internal import StackKit

/// The bucket frames this project keeps on disk between runs: how much, and where.
package nonisolated struct KeptFrames: Equatable, Sendable {
  /// What they take on disk.
  package var bytes: Int64
  /// The folder of this project's copies.
  package var folder: URL
  /// The scratch folder it was read under: what a removal is checked against.
  package var scratch: URL

  /// `bytes` kept in `folder`, under `scratch`.
  package init(bytes: Int64, folder: URL, scratch: URL) {
    self.bytes = bytes
    self.folder = folder
    self.scratch = scratch
  }
}

/// The bucket frames a project keeps between runs (card 0191), their size shown and their removal
/// offered once an export is made (card 0192): only the copies this app downloaded, never a
/// capture of this Mac, never anything in a bucket.
extension ProjectWindowModel {
  /// Reads again what the project keeps of its bucket frames, off the main actor: after a scan,
  /// after a run and after a removal, the moments it can change.
  func refreshKeptFrames() {
    // A removal owns the folder until it ends, and reads it again itself.
    guard !isRemovingKeptFrames else { return }
    keptFramesTask?.cancel()
    guard let cache = remoteFrameCache else {
      (keptRemoteFrames, keptFramesCache, keptFrames, keptFramesTask) = ([], nil, nil, nil)
      return
    }
    let paths = (scan?.inventory.frames ?? []).map(\.path)
      .filter { ProjectSource.remoteParts(of: $0) != nil }
    let scratch = runs.scratch
    keptFramesTask = Task {
      guard let read = await cache.readOffActor(among: paths), !Task.isCancelled else { return }
      keptRemoteFrames = read.kept
      // Without a bucket frame in the scan nothing was looked up: the budget is the local one.
      keptFramesCache = paths.isEmpty ? nil : cache
      keptFrames =
        read.bytes > 0
        ? KeptFrames(bytes: read.bytes, folder: cache.root, scratch: scratch) : nil
      keptFramesTask = nil
    }
  }

  /// What a queue of runs left on disk, read once it ends and when the window opens: the stacks
  /// no row names (card 0113) and the bucket frames kept (card 0191).
  func readWhatTheRunsLeft() {
    listLeftoverStacks()
    refreshKeptFrames()
  }

  /// Waits for the read or the removal of the kept frames in flight, if any.
  package func keptFramesSettled() async {
    while let task = keptFramesTask {
      await task.value
      if task == keptFramesTask { return }
    }
  }

  /// The Export stage offers the removal: something is kept, and the journey reads the export
  /// as done (`JourneyState`) — before that, the frames may still be wanted for another run.
  package var offersKeptFramesRemoval: Bool {
    keptFrames != nil && statuses[.export] == .done
  }

  /// The kept frames can be removed now: there are some, no run is linking them into a lane,
  /// and no removal is already going.
  package var canRemoveKeptFrames: Bool {
    keptFrames != nil && !isStacking && !isRemovingKeptFrames
  }

  /// Deletes the kept bucket frames the stage shows; the next run downloads them again.
  ///
  /// Exactly the folder `keptFrames` names and the dialog confirmed — never one recomputed from
  /// a setting that changed since (values applied = values shown, R2) — and only when
  /// `RemoteFrameCache.isRemovable` allows it: never a capture night, the library or the
  /// package, which are named to it. Run waits while it goes (`canRun`). A refusal or a failure
  /// is shown; nothing while a run is going.
  package func removeKeptFrames() {
    guard canRemoveKeptFrames, let kept = keptFrames else { return }
    let cache = RemoteFrameCache(root: kept.folder)
    // The app's one list of what no deletion touches (the astro folder chosen and the default
    // one, the app's data), then this project's own: its folders of this Mac and its package.
    let protected =
      AppDelegate.protectedFolders() + [ImportPlanning.libraryFolder]
      + sources.filter { $0.kind != .remoteNight }.map { URL(fileURLWithPath: $0.path) }
      + [folder()].compactMap { $0 }
    keptFramesTask?.cancel()
    isRemovingKeptFrames = true
    keptFramesTask = Task {
      do {
        try await cache.removeOffActor(scratch: kept.scratch, protected: protected)
      } catch {
        self.error = UserFacingError(error)
      }
      isRemovingKeptFrames = false
      refreshKeptFrames()
    }
  }
}

nonisolated extension RemoteFrameCache {
  /// The frames of `paths` kept and the bytes every kept frame takes, read off the caller's
  /// actor: file checks and a digest a frame, then a walk of the folder. `nil` when the read
  /// was cancelled between the two (a newer read replaced it).
  @concurrent
  func readOffActor(among paths: [String]) async -> (kept: Set<String>, bytes: Int64)? {
    let kept = kept(among: paths)
    guard !Task.isCancelled else { return nil }
    return (kept, size())
  }

  /// `remove(scratch:protected:)` off the caller's actor.
  @concurrent
  func removeOffActor(scratch: URL, protected: [URL]) async throws {
    try remove(scratch: scratch, protected: protected)
  }
}
