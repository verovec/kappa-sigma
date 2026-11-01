import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0157: revising applied step k re-applies it with new values, replays k+1… with their
/// recorded ones up to the first host tool, and keeps the old chain as a version.
extension StudioModelTests {
  /// The project's studio with stretch, curves, saturation applied after the combination.
  static func fourApplied(_ opened: Opened) throws -> StudioModel {
    let studio = try Self.model(opened)
    for id in [StretchProcess.id, CurvesProcess.id, SaturationProcess.id] {
      try studio.apply(
        id, params: ParamSet(schema: try #require(studio.session.registry.type(id: id)).schema))
    }
    return studio
  }

  static func stretch(target: Double) throws -> ParamSet {
    var params = ParamSet(schema: StretchProcess.schema)
    try params.set("targetBackground", .number(target))
    return params
  }

  @Test("testReviseStep_ReplaysTailWithRecordedValues", .scratchDirectory)
  func testReviseStep_ReplaysTailWithRecordedValues() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.fourApplied(opened)
    let before = studio.steps
    let revised = try Self.stretch(target: 0.4)

    let applied = try await studio.reviseStep(1, params: revised)

    #expect(applied == 4)
    #expect(studio.steps.map(\.processID) == before.map(\.processID))
    #expect(studio.steps[1].params == revised)
    #expect(
      studio.steps[2].params == before[2].params && studio.steps[3].params == before[3].params)
    #expect(studio.steps[0].file == before[0].file, "the steps before k are kept as they are")
    #expect(studio.session.history.versions.last?.steps == Array(before[1...]))
    let head = studio.head.planes

    // The same chain applied by hand, from the combination, gives the same head.
    try studio.undo(steps: 3)
    try studio.apply(StretchProcess.id, params: revised)
    try studio.apply(CurvesProcess.id, params: before[2].params)
    try studio.apply(SaturationProcess.id, params: before[3].params)
    #expect(studio.head.planes == head)
  }

  @Test("testReviseStep_StopsBeforeHostTool", .scratchDirectory)
  func testReviseStep_StopsBeforeHostTool() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.model(opened)
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [.starless: studio.head])
    try studio.apply(SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema))
    let before = studio.steps

    let applied = try await studio.reviseStep(1, params: try Self.stretch(target: 0.3))

    #expect(applied == 2, "the tool step and what follows it wait for ▶ Run")
    #expect(studio.steps.map(\.processID) == ["channel-combination", StretchProcess.id])
    #expect(studio.session.history.versions.last?.steps == Array(before[1...]))
  }

  @Test(
    "a host-tool step revised without its tool is refused before anything moves",
    .scratchDirectory)
  func testReviseStep_ToolStepNeedsItsTool() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.model(opened)
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [.starless: studio.head])
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    let before = studio.steps

    await #expect(throws: PipelineError.toolMissing(StarSeparation.id)) {
      try await studio.reviseStep(1, params: ParamSet(schema: StarSeparation.schema))
    }
    #expect(studio.steps == before && studio.session.history.versions.isEmpty)

    // With its tool: the tool runs as step k, the GPU steps after it replay.
    let run:
      @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void) async throws
        -> AstroImage = { image, _, progress in
          progress(1)
          return image
        }
    let tool = PipelineRunner.BatchProcess(
      schema: StarSeparation.schema, writes: .starless, run: run)
    let applied = try await studio.reviseStep(
      1, params: ParamSet(schema: StarSeparation.schema), tool: tool)
    #expect(applied == 3 && studio.steps.map(\.processID) == before.map(\.processID))
    #expect(studio.steps[1].file != before[1].file, "the tool ran again")
  }

  @Test("a step past the applied ones is refused", .scratchDirectory, arguments: [-1, 1, 7])
  func testReviseStep_OutOfRange(index: Int) async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.model(opened)
    await #expect(throws: HistoryError.noStep(index)) {
      try await studio.reviseStep(index, params: ParamSet(schema: StretchProcess.schema))
    }
    #expect(studio.steps.count == 1)
  }
}
