import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

/// "Rebuild from the capture" with the real Siril: the two −19 °C darks of M31-DB stacked into
/// a scratch library (never the real one), measured afterwards.
@Suite(
  "Live master rebuild — Siril stacks an M31-DB dark into a scratch library", .liveFixtures,
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveMasterRebuildTests {
  @Test(
    "the rebuilt dark lands in the library with its .sig, and reads back",
    .scratchDirectory)
  func testLiveMasterRebuild() async throws {
    let capture = ImportPlanning.capturesFolder.appendingPathComponent("M31-DB")
    guard FileManager.default.fileExists(atPath: capture.path), (try? SirilTool.locate()) != nil
    else { try Test.cancel("M31-DB or Siril absent") }
    let library = try ScratchDirectory.url.appendingPathComponent("library")
    let paris = try #require(TimeZone(identifier: "Europe/Paris"))
    let plan = try ImportPlanner(builder: InventoryBuilder(timeZone: paris))
      .plan(ImportRequest(paths: [capture.path]), library: [])
    let darks = try #require(plan.inventory.sets.first { $0.key.type == .dark && $0.count == 2 })
    let builder = MasterBuilder(runner: .live(binary: try SirilTool.locate()))

    let result = try await ImportPlanning.rebuild(
      darks, of: plan.inventory, pool: [], library: library, builder: builder)

    let master = try #require(result.masters.first)
    #expect(master.path.hasPrefix(library.path))
    #expect(FileManager.default.fileExists(atPath: PoolSignature.sidecar(of: master.path)))
    let inspection = try MasterInspection.read(master.path)
    #expect(inspection.frames == 2)
    #expect(inspection.stats.hotPixels != nil)
  }
}
