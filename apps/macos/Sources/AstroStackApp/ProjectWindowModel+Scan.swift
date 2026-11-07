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
      // A project whose captures are all in buckets: the remote sources alone (card 0169).
      guard let planned = try runRequest() else { return startRemoteScan() }
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
        rescanAfterAdd = false
        scanTask = nil
        refresh()
        // After the local plan, never before it: one unreachable bucket would otherwise hold
        // back a purely local Rescan — and Run with it (card 0100's `awaitsRescan`). Its own
        // task, so Cancel and the next Rescan still reach it (card 0182).
        startRemoteScan()
      } catch {
        guard !Task.isCancelled else { return }
        // The folders no longer read as scanned: the last scan stops describing them. A
        // cancellation from inside the planner (not ours) ends the scan without an error.
        dropScan()
        refresh()
        if !(error is CancellationError) { self.error = UserFacingError(error) }
        // A folder that does not read never keeps the buckets from being read (card 0182).
        startRemoteScan()
      }
    }
  }

  /// Stops the scan in flight, the buckets' too (card 0182): the user's Cancel, a new Rescan, a
  /// closing window.
  ///
  /// The previous scan, if any, and each bucket's last count stay shown.
  package func cancelScan() {
    cancelLocalScan()
    cancelRemoteScan()
  }

  /// Stops the plan of this Mac's folders only: what Add and Run replace (card 0182), while a
  /// bucket read in flight goes on — it reads no folder Add or Run plans.
  func cancelLocalScan() {
    scanTask?.cancel()
    scanTask = nil
    isScanning = false
    rescanAfterAdd = false
  }

  /// Waits for the scan in flight, if any: the local plan, then the buckets it started.
  package func scanSettled() async {
    await scanTask?.value
    await remoteScanTask?.value
  }

  /// After Add: the sheet's plan becomes the window's scan only when it is settled (planned for
  /// `request`, nothing in flight) and `request` is the one a run would apply (every capture
  /// night, the stored and this session's choices); otherwise the previous scan no longer
  /// describes the project and is dropped until the user rescans.
  func adoptScan(of sheet: ImportViewModel?, for request: ImportRequest) {
    guard let sheet, let plan = sheet.plan, !sheet.isScanning, sheet.request == request,
      let run = try? runRequest(), Self.sameRequest(request, run)
    else { return dropScan() }
    cancelLocalScan()
    scan = plan
  }

  /// The project changed in a way the last scan of its folders does not describe.
  func dropScan() {
    cancelLocalScan()
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
    Set(lhs.map(standardPath)) == Set(rhs.map(standardPath))
  }

  /// A folder as the store records it (a standardized file path).
  static func standardPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }
}
