import Foundation
import ProjectKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Rebuilding one master from the Import sheet (card 0071): into the shared library through the
/// atomic writer, Siril's progress forwarded, and the plan matching the new master.
extension MasterBuilderTests {
  @Test(
    "a rebuild lands in the library atomically, streams progress, and the plan re-matches it",
    .scratchDirectory)
  func testBuildProgressAndRematch() async throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try Self.scan("golden-single-night", under: root)
    let library = root.appendingPathComponent("library")
    let darks = try #require(inventory.sets.first { $0.key.type == .dark })
    let siril = RecordingSiril()
    let lines = Mutex<[SirilLine]>([])
    let talking = SirilRunner(run: { script, directory, onLine in
      onLine(SirilLine(parsing: "log: Stacking, 50%"))
      return try await siril.runner.run(script, directory, onLine)
    })
    let builder = MasterBuilder(
      runner: talking, onLine: { line in lines.withLock { $0.append(line) } })

    let result = try await builder.rebuild(
      darks, of: inventory, library: library, work: root.appendingPathComponent("work"))

    let master = try #require(result.masters.first)
    #expect(
      master.path
        == library.appendingPathComponent(MasterName.make(darks.key, recipe: "") + ".fits").path)
    #expect(siril.calls.first?.script.contains("/.tmp_rebuild_") == true, "the atomic writer")
    #expect(lines.withLock { $0.map(\.percent) } == [50])
    #expect(FileManager.default.fileExists(atPath: PoolSignature.sidecar(of: master.path)))

    let project = try ProjectPackage.create(at: root.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    try CalibrationLibrary(folder: library).reindex(into: project.store)
    let plan = ImportPlan(
      inventory: inventory, library: try CalibrationLibrary.masters(in: project.store),
      request: ImportRequest(paths: [root.path]))
    let lum = try #require(plan.calibration.first { $0.filter == "L" })
    #expect(lum.cells.first?.status == .library(path: master.path, frames: 3))
  }

  @Test(
    "a rebuild over an existing library master asks first, then really stacks — even proven frames",
    .scratchDirectory)
  func testRebuildReplacesOnlyWhenAsked() async throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try Self.scan("golden-single-night", under: root)
    let library = root.appendingPathComponent("library")
    let work = root.appendingPathComponent("work")
    let darks = try #require(inventory.sets.first { $0.key.type == .dark })
    let siril = RecordingSiril()
    let builder = MasterBuilder(runner: siril.runner)
    let first = try #require(
      try await builder.rebuild(darks, of: inventory, library: library, work: work).masters.first)
    var proven = first
    proven.fromLibrary = true

    await #expect(throws: CalibrationError.wouldReplace(path: first.path, frames: 3)) {
      try await builder.rebuild(darks, of: inventory, library: library, work: work, pool: [proven])
    }
    #expect(siril.calls.count == 1, "nothing stacked before the user agreed")

    let again = try await builder.rebuild(
      darks, of: inventory, library: library, work: work, pool: [proven], replace: true)
    #expect(siril.calls.count == 2, "its own proven master is not reused by a rebuild")
    #expect(again.masters.first?.path == first.path)
  }
}
