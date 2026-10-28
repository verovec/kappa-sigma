import Foundation
import StackKit
import TestSupport
import Testing

/// A run with no colour to build still ends on a combined image (card 0137): its one mono master
/// copied, previewed like a composite, the journal saying which master it is.
extension PreprocessorTests {
  @Test(
    "a mono run previews its combined image and notes the master it copied",
    .scratchDirectory,
    arguments: [
      (["L"], "L", ["master_L", "combined"]),
      (["R", "G"], "R", ["master_R", "master_G", "combined"]),
    ] as [([String], String, [String])])
  func testMonoRunPreviewsTheComposite(filters: [String], base: String, previews: [String])
    async throws
  {
    let full = try Self.request("mono-\(base)")
    let lights = full.inventory.sets.filter {
      $0.key.type == .light && filters.contains($0.key.filter)
    }
    let scope = RunScope(
      object: "TESTFIELD", setIDs: lights.map(\.key.id),
      lights: lights.map(\.indices.count).reduce(0, +))
    let request = PreprocessRequest(
      inventory: full.inventory.scoped(scope), output: full.output, work: full.work,
      runID: full.runID)

    let (events, error) = await Self.collect(
      Preprocessor(tools: Self.tools(PipelineSiril())).run(request))

    #expect(error == nil)
    let stages = events.compactMap { event -> String? in
      if case .preview(let preview) = event { return preview.stage }
      return nil
    }
    #expect(stages == previews)
    guard case .finished(let result) = try #require(events.last) else {
      Issue.record("the last event is not .finished")
      return
    }
    #expect(result.combinedPath?.hasSuffix("/combined.fits") == true)
    #expect(result.notes.contains("combined = \(base) alone (mono: no colour composite to build)"))
  }
}
