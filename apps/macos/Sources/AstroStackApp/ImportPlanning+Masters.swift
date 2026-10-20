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
    let planning: ImportViewModel.Planning = { request in
      try await plan(request, index: index, timeZone: timeZone)
    }
    let masters = MasterServices(
      inspect: { path in try await inspect(path) },
      rebuild: { set, inventory, pool, replace, onLine in
        let builder = MasterBuilder(runner: .live(binary: try SirilTool.locate()), onLine: onLine)
        let result = try await rebuild(
          set, of: inventory, pool: pool, library: library, replace: replace, builder: builder)
        await index.invalidate()
        return result
      },
      preview: { path in ImageViewerWindow.show(URL(fileURLWithPath: path)) })
    return ImportServices(planning: planning, masters: masters)
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
