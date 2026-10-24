import ProcessKit
import Testing

/// Card 0116: the usual processing order — one list, every registered process once, linear work
/// before the stretch, the finish after; « usually next » is a suggestion only (R2).
@Suite("ProcessOrder — the usual order of the Studio's processes")
struct ProcessOrderTests {
  @Test("every registered process is in the usual order exactly once")
  func testUsual_CoversEveryRegisteredProcessOnce() throws {
    let ids = try ProcessRegistry.standard().ids
    #expect(Set(ProcessOrder.usual).count == ProcessOrder.usual.count)
    #expect(Set(ProcessOrder.usual) == Set(ids))
  }

  @Test("linear work comes before the stretch, the finish after it")
  func testStagesInOrder() throws {
    let registry = try ProcessRegistry.standard()
    let stretch = try #require(ProcessOrder.rank(of: StretchProcess.id))
    for id in ProcessOrder.usual where id != StretchProcess.id {
      let type = try #require(registry.type(id: id))
      let rank = try #require(ProcessOrder.rank(of: id))
      if type.stage == .linear { #expect(rank < stretch, "\(id)") }
      if type.stage == .nonlinear { #expect(rank > stretch, "\(id)") }
    }
    let bge = try #require(ProcessOrder.rank(of: BackgroundExtractionProcess.id))
    #expect(bge < stretch, "the PO's case: background extraction first")
  }

  struct Next: Sendable, CustomTestStringConvertible {
    var applied: [String]
    var next: String?
    var testDescription: String { "\(applied) → \(next ?? "nil")" }
  }

  static let nexts = [
    Next(applied: ["channel-combination"], next: BackgroundExtractionProcess.id),
    Next(applied: ["channel-combination", "stretch"], next: LevelsProcess.id),
    Next(applied: ["channel-combination", "stretch", "levels"], next: CurvesProcess.id),
    Next(applied: ["channel-combination", "geometry"], next: BackgroundExtractionProcess.id),
    Next(applied: ["channel-combination", "starnet"], next: BackgroundExtractionProcess.id),
    Next(applied: ["channel-combination", "star-recomposition"], next: nil),
    Next(applied: [], next: ChannelCombinationProcess.id),
  ]

  @Test("usually next: the process after the last ordered step, never geometry", arguments: nexts)
  func testUsuallyNext(_ row: Next) {
    #expect(ProcessOrder.usuallyNext(after: row.applied) == row.next)
  }
}
