internal import Foundation
internal import ProjectKit
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
      // The folders' request does not hold: the buckets are read all the same (card 0182).
      return startRemoteScan()
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
        // After the plan, never before it, and in a task of its own, so Cancel and the next
        // Rescan still reach it (card 0182): each bucket row is read again for its own count —
        // the plan above already read them with the folders (card 0190), and what it kept of
        // each prefix (card 0168) spares these reads their headers.
        startRemoteScan()
      } catch {
        guard !Task.isCancelled else { return }
        // The folders no longer read as scanned: the last scan stops describing them. A
        // cancellation from inside the planner (not ours) ends the scan without an error.
        dropScan()
        refresh()
        if !(error is CancellationError) { self.error = UserFacingError(error) }
        // The plan failed as a whole (R2: never the readable half alone); each bucket is then
        // read on its own, so its row says which one refuses and why (card 0182).
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

  /// Stops the plan of this Mac's folders only (card 0182): what Run and an adopted Add replace.
  ///
  /// A bucket read in flight goes on, since it plans no folder; an Add followed by a Rescan stops
  /// it like any Rescan, and reads it again after the folders.
  func cancelLocalScan() {
    scanTask?.cancel()
    scanTask = nil
    isScanning = false
    rescanAfterAdd = false
  }

  /// Waits for the scan in flight, if any: the local plan, then the buckets it started, and any
  /// scan that replaced one of them meanwhile.
  package func scanSettled() async {
    while let task = scanTask ?? remoteScanTask {
      await task.value
      // A task that ended without letting go of its slot (none does today) must not spin here.
      if task == scanTask || task == remoteScanTask { return }
    }
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

  /// The capture nights among the sources, wherever they are read from (card 0190).
  ///
  /// Folders of this Mac and bucket prefixes, in the order they were imported. A legacy run
  /// (0043) is a source, never a capture.
  package var nightPaths: [String] {
    sources.filter { $0.kind == .night || $0.kind == .remoteNight }.map(\.path)
  }

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

  /// A night as the store records it: a standardized file path, or a bucket prefix's virtual
  /// path as it is.
  static func standardPath(_ path: String) -> String {
    guard ProjectSource.remoteFolder(of: path) == nil else { return path }
    return URL(fileURLWithPath: path).standardizedFileURL.path
  }
}
