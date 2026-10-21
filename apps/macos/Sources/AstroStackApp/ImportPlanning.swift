package import Foundation
package import ProjectKit
package import StackKit

/// The planner the Import sheet runs: the calibration library indexed into the project, then the
/// capture scanned and matched, all off the main actor.
package enum ImportPlanning {
  /// Where captures are suggested from (R7: read-only, outside every repo).
  package nonisolated static var capturesFolder: URL { astro.appendingPathComponent("captures") }
  /// The calibration library reused as is.
  package nonisolated static var libraryFolder: URL { astro.appendingPathComponent("library") }

  private nonisolated static var astro: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/astro")
  }

  /// A planning closure over the project's `store` and the library at `library`; the library is
  /// indexed once per closure (one Import sheet), not on every rescan.
  package nonisolated static func live(
    store: ProjectStore?, library: URL = libraryFolder, timeZone: TimeZone = .current
  ) -> ImportViewModel.Planning {
    ImportViewModel.silent(services(store: store, library: library, timeZone: timeZone).planning)
  }

  /// Plans `request` against the library `index` holds; without a library every master is one
  /// the capture would build. `progress` hears `.library`, then the scan's own steps.
  @concurrent
  package nonisolated static func plan(
    _ request: ImportRequest, index: LibraryIndex, timeZone: TimeZone,
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> ImportPlan {
    progress(.library)
    let masters = try await index.masters()
    try Task.checkCancellation()
    return try ImportPlanner(builder: InventoryBuilder(timeZone: timeZone))
      .plan(request, library: masters, progress: progress)
  }
}
