internal import Foundation
internal import StackKit

/// The Données stage's scan (0078): Rescan on demand over the capture nights, through the same
/// planner as the Import sheet and with the request a Run would apply (`runRequest`), so the
/// coverage shown is the calibration the run will use (R2); the integration and coverage are read
/// off the plan once.
extension ProjectWindowModel {
  /// Scans the capture nights again with the run's request, cancelling a scan in flight; nothing
  /// without a capture night.
  package func rescan() {
    cancelScan()
    guard let store = store() else {
      error = .projectClosed
      return
    }
    let request: ImportRequest
    do {
      guard let planned = try runRequest() else { return }
      request = planned
    } catch {
      self.error = UserFacingError(error)
      return
    }
    let planning = ImportViewModel.silent(services(store).planning)
    isScanning = true
    scanTask = Task {
      do {
        let plan = try await planning(request)
        guard !Task.isCancelled else { return }
        // A night recorded while it ran is not in this plan: show nothing rather than a part.
        if Self.samePaths(request.paths, nightPaths) { scan = plan } else { dropScan() }
        isScanning = false
        scanTask = nil
        refresh()
      } catch {
        guard !Task.isCancelled else { return }
        // The folders no longer read as scanned: the last scan stops describing them. A
        // cancellation from inside the planner (not ours) ends the scan without an error.
        dropScan()
        refresh()
        if !(error is CancellationError) { self.error = UserFacingError(error) }
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
  /// `request`, nothing in flight) and `request` is the one a run would apply (every capture
  /// night, the stored and this session's choices); otherwise the previous scan no longer
  /// describes the project and is dropped until the user rescans.
  func adoptScan(of sheet: ImportViewModel?, for request: ImportRequest) {
    guard let sheet, let plan = sheet.plan, !sheet.isScanning, sheet.request == request,
      let run = try? runRequest(), Self.sameRequest(request, run)
    else { return dropScan() }
    cancelScan()
    scan = plan
  }

  /// The project changed in a way the last scan does not describe.
  func dropScan() {
    cancelScan()
    scan = nil
  }

  /// The capture nights among the sources: a legacy run (0043) is a source, never a capture.
  var nightPaths: [String] { sources.filter { $0.kind == .night }.map(\.path) }

  /// The same request, its folders compared as the store records them.
  static func sameRequest(_ lhs: ImportRequest, _ rhs: ImportRequest) -> Bool {
    var aligned = lhs
    aligned.paths = rhs.paths
    return samePaths(lhs.paths, rhs.paths) && aligned == rhs
  }

  /// The same folders, compared as the store records them (standardized file paths).
  static func samePaths(_ lhs: [String], _ rhs: [String]) -> Bool {
    let standard = { (paths: [String]) in
      Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }
    return standard(lhs) == standard(rhs)
  }
}
