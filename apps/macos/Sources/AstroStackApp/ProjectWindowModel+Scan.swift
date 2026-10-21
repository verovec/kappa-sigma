internal import StackKit

/// The Données stage's scan (0078): Rescan on demand over the recorded sources, through the same
/// planner as the Import sheet; the integration and coverage are read off the plan once.
extension ProjectWindowModel {
  /// Scans the recorded sources again, cancelling a scan in flight; nothing without sources.
  ///
  /// The last scan's import choices (filter map, exclusions, clip filters, unchecked masters)
  /// are kept while the sources are the same, so a Rescan never silently changes the verdict.
  package func rescan() {
    cancelScan()
    let paths = sources.map(\.path)
    guard !paths.isEmpty else { return }
    guard let store = store() else {
      error = .projectClosed
      return
    }
    let request =
      scanRequest.flatMap { Set($0.paths) == Set(paths) ? $0 : nil } ?? ImportRequest(paths: paths)
    let planning = services(store).planning
    isScanning = true
    scanTask = Task {
      do {
        let plan = try await planning(request)
        guard !Task.isCancelled else { return }
        scanRequest = request
        scan = plan
        isScanning = false
        refresh()
      } catch {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        isScanning = false
        self.error = UserFacingError(error)
      }
    }
  }

  /// Stops the scan in flight; the previous scan, if any, stays shown.
  package func cancelScan() {
    scanTask?.cancel()
    scanTask = nil
    isScanning = false
  }

  /// Waits for the scan in flight, if any.
  package func scanSettled() async {
    await scanTask?.value
  }

  /// After Add: the sheet's plan becomes the window's scan only when it is settled (planned for
  /// `request`, nothing in flight) and covers every recorded source; otherwise the previous scan
  /// no longer describes the project and is dropped until the user rescans.
  func adoptScan(of sheet: ImportViewModel?, for request: ImportRequest, sources: [String]) {
    cancelScan()
    if let sheet, let plan = sheet.plan, !sheet.isScanning, sheet.request == request,
      Set(request.paths) == Set(sources)
    {
      scanRequest = request
      scan = plan
    } else {
      scanRequest = nil
      scan = nil
    }
  }
}
