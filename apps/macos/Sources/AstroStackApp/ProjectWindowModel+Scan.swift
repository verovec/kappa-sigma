package import StackKit

/// The Données stage's scan (0078): Rescan on demand over the recorded sources, through the same
/// planner as the Import sheet; its integration and coverage are read off the plan.
extension ProjectWindowModel {
  /// The lights per filter × night of the last scan.
  package var integration: IntegrationSummary? {
    scan.map { IntegrationSummary.make(inventory: $0.inventory) }
  }

  /// The calibration coverage of the last scan, the matcher's verdict as is.
  package var coverage: CoverageMatrix? { scan.map(CoverageMatrix.init(plan:)) }

  /// Scans the recorded sources again, cancelling a scan in flight; nothing without sources.
  package func rescan() {
    cancelScan()
    let paths = sources.map(\.path)
    guard !paths.isEmpty else { return }
    let planning = services(store()).planning
    isScanning = true
    scanTask = Task {
      do {
        let plan = try await planning(ImportRequest(paths: paths))
        guard !Task.isCancelled else { return }
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
}
