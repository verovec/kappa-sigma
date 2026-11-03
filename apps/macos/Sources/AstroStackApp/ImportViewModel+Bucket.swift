internal import StackKit

// MARK: - Importing a bucket prefix (card 0169), and the scan's plumbing

extension ImportViewModel {
  /// Moves the sheet between « folders of this Mac » and « bucket »; nothing is scanned until
  /// something is chosen, so the choice alone never reads anything.
  package func setSource(_ source: Source) {
    self.source = source
  }

  /// Starts over on the bucket prefix `target`: it is scanned where it stands, never downloaded,
  /// and the project will record it as the source it is (card 0168).
  ///
  /// Like a change of capture folder, it keeps no override and no profile choice.
  package func choose(bucket target: RemoteImportTarget) {
    source = .bucket
    remoteTarget = target
    request = ImportRequest(paths: [target.path])
    droppedFolders = []
    panelError = nil
    excludedRows = []
    profileChoice = .proposed
    // Always a fresh read: the connection is not part of the request, so the same prefix read
    // through another connection would otherwise be « replanned » from the first one's scan.
    rescan()
  }

  /// `request` planned by whichever side it names.
  ///
  /// The bucket when one was chosen, the disk otherwise: a virtual path is never handed to the
  /// disk scanner.
  func planned(
    _ request: ImportRequest, progress: @escaping @Sendable (ScanProgress) -> Void
  ) async throws -> ImportPlan {
    guard let remoteTarget else { return try await planning(request, progress) }
    guard let remotePlanning else { throw CancellationError() }
    return try await remotePlanning(remoteTarget, request, progress)
  }

  /// `planned(request)`, called from the scan task itself (scans start in the order the controls
  /// asked), its progress consumed by a child task into `progress` (newest value only: the sheet
  /// shows where the scan is, not every step it took).
  func scanReporting(_ request: ImportRequest) async throws -> ImportPlan {
    let (steps, continuation) = AsyncStream.makeStream(
      of: ScanProgress.self, bufferingPolicy: .bufferingNewest(1))
    async let watched: Void = watch(steps)
    // Finished before the watcher is awaited; the defer covers a planning that throws.
    defer { continuation.finish() }
    let plan = try await planned(request) { continuation.yield($0) }
    continuation.finish()
    await watched
    return plan
  }

  /// Shows each step of `steps` until the stream ends or the scan is cancelled.
  private func watch(_ steps: AsyncStream<ScanProgress>) async {
    for await step in steps where !Task.isCancelled { progress = step }
  }
}
