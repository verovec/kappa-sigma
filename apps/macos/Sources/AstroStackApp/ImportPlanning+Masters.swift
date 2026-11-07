package import Foundation
package import ProjectKit
package import StackKit

extension ImportPlanning {
  /// The live services of one sheet: planning and rebuilds share the library index, so a rebuilt
  /// master is indexed by the next scan.
  package nonisolated static func services(
    store: ProjectStore?, library: URL = libraryFolder, timeZone: TimeZone = .current
  ) -> ImportServices {
    let index = LibraryIndex(store: store, folder: library)
    let planning: ImportViewModel.ProgressPlanning = { request, progress in
      try await plan(request, index: index, timeZone: timeZone, progress: progress)
    }
    let masters = MasterServices(
      inspect: { path in try await inspect(path) },
      rebuild: { set, inventory, pool, replace, onLine in
        var builder = MasterBuilder(runner: .live(binary: try SirilTool.locate()), onLine: onLine)
        // A set scanned out of a bucket is rebuilt from that bucket (card 0154), through the
        // connection its source row names — not refused for want of a store.
        // A set of this Mac's frames never asks the Keychain (no prompt for a local rebuild).
        let paths = set.frames.map(\.path)
        if paths.contains(where: { ProjectSource.remoteParts(of: $0) != nil }) {
          let buckets = await runStores((try? store?.sources() ?? []) ?? [])
          if let refusal = buckets.refusal(reading: paths) { throw refusal }
          builder.stager = FrameStager(stores: buckets.stores)
        }
        let result = try await rebuild(
          set, of: inventory, pool: pool, library: library, replace: replace, builder: builder)
        await index.invalidate()
        return result
      },
      preview: { path in ImageViewerWindow.show(URL(fileURLWithPath: path)) })
    return ImportServices(
      planning: planning, masters: masters,
      remotePlanning: remotePlanning(store: store, index: index, timeZone: timeZone),
      browsing: browsing())
  }

  /// Measures the master at `path` off the main actor.
  @concurrent
  package nonisolated static func inspect(_ path: String) async throws -> MasterInspection {
    try MasterInspection.read(path)
  }

  /// Rebuilds `set` into `library` with `builder`, in a scratch folder removed afterwards.
  @concurrent
  package nonisolated static func rebuild(
    _ set: FrameSet, of inventory: Inventory, pool: [CalibrationMaster], library: URL,
    replace: Bool = false, builder: MasterBuilder
  ) async throws -> MasterBuilder.Result {
    let work = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/rebuild-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: work) }
    return try await builder.rebuild(
      set, of: inventory, library: library, work: work, pool: pool, replace: replace)
  }
}
