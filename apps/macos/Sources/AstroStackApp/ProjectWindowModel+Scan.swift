internal import Foundation
internal import StackKit

/// The Données stage's scan (0078): Rescan on demand over the recorded sources, through the same
/// planner as the Import sheet; the integration and coverage are read off the plan once.
extension ProjectWindowModel {
  /// Scans the recorded sources again, cancelling a scan in flight; nothing without sources.
  ///
  /// The adopted sheet's import choices (filter map, exclusions, clip filters, unchecked masters)
  /// are kept while the sources are the ones it covered. Choices of an earlier sheet are not
  /// merged: until 0057 persists the request, a project grown over two imports rescans with the
  /// scan's defaults, which the pane then shows as is.
  package func rescan() {
    cancelScan()
    let paths = sources.map(\.path)
    guard !paths.isEmpty else { return }
    guard let store = store() else {
      error = .projectClosed
      return
    }
    let request =
      scanRequest.flatMap { Self.samePaths($0.paths, paths) ? $0 : nil }
      ?? ImportRequest(paths: paths)
    let planning = services(store).planning
    isScanning = true
    scanTask = Task {
      do {
        let plan = try await planning(request)
        guard !Task.isCancelled else { return }
        scanRequest = request
        scan = plan
        isScanning = false
        scanTask = nil
        refresh()
      } catch {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        isScanning = false
        scanTask = nil
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
    if let sheet, let plan = sheet.plan, !sheet.isScanning, sheet.request == request,
      Self.samePaths(request.paths, sources)
    {
      cancelScan()
      scanRequest = request
      scan = plan
    } else {
      dropScan()
    }
  }

  /// The project changed in a way the last scan does not describe.
  func dropScan() {
    cancelScan()
    scanRequest = nil
    scan = nil
  }

  /// The same folders, compared as the store records them (standardized file paths).
  static func samePaths(_ lhs: [String], _ rhs: [String]) -> Bool {
    let standard = { (paths: [String]) in
      Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }
    return standard(lhs) == standard(rhs)
  }
}
