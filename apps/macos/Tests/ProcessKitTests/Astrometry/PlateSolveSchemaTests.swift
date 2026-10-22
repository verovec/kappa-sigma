import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0093: the plate-solve process's declaration — header values as suggestions, text values,
/// and a host tool the pipeline never replaces by its preview.
@Suite("PlateSolveProcess: suggestions, text values, host tool")
struct PlateSolveSchemaTests {
  static func header(_ cards: [(String, String)]) throws -> FITSHeader {
    var text = cards.map {
      ($0.0.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + $0.1)
        .padding(toLength: 80, withPad: " ", startingAt: 0)
    }.joined()
    text += "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return try FITSFile.parse(Data(text.utf8)).header
  }

  static let reason = PlateSolveProcess.fromHeader

  @Test(
    "the header's pointing and optics, one suggestion each",
    arguments: [
      (
        [("OBJCTRA", "'00 42 49.089'"), ("OBJCTDEC", "'+41 16 15.592'"), ("RA", "10.7")],
        [("ra", ParamValue.text("00 42 49.089")), ("dec", .text("+41 16 15.592"))]
      ),
      (
        [("RA", "10.7045385138686"), ("DEC", "-5.25")],
        [("ra", .text("10.704539")), ("dec", .text("-5.25"))]
      ),
      (
        [("FOCALLEN", "249."), ("XPIXSZ", "3.76")],
        [("focalMm", .number(249)), ("pixelSizeUm", .number(3.76))]
      ),
      ([("FOCALLEN", "0"), ("XPIXSZ", "99"), ("OBJCTRA", "'00 42 49'")], []),
    ])
  func testHeaderSuggestions(cards: [(String, String)], expected: [(String, ParamValue)]) throws {
    let suggestions = PlateSolveProcess.suggestions(header: try Self.header(cards))
    #expect(
      suggestions
        == expected.map { Suggestion(paramID: $0.0, value: $0.1, reason: Self.reason) })
  }

  @Test("no header, no suggestion")
  func testNoHeader() {
    #expect(PlateSolveProcess.suggestions(header: nil).isEmpty)
  }

  @Test("a text value: kept as typed, read back from JSON's string, refused when too long")
  func testTextValues() throws {
    var params = ParamSet(schema: PlateSolveProcess.schema)
    #expect(params.text("ra").isEmpty)
    try params.set("ra", .text("00 "))
    #expect(params.text("ra") == "00 ", "a space typed stays: the field binds every keystroke")
    try params.set("ra", .text("00 42 44"))
    let json = try JSONEncoder().encode(params)
    let entries = try JSONDecoder().decode([ParamSet.Entry].self, from: json)
    let loaded = ParamSet.loading(entries, onto: PlateSolveProcess.schema)
    #expect(loaded.rejected.isEmpty)
    #expect(loaded.params == params)
    #expect(throws: ParamError.tooLong(id: "ra")) {
      try params.set("ra", .text(String(repeating: "1", count: 41)))
    }
    #expect(throws: ParamError.wrongKind(id: "ra")) { try params.set("ra", .number(1)) }
    #expect(params.number("ra") == 0 && ParamSet(schema: StretchProcess.schema).text("mode") == "")
  }

  @Test("a too-long text default is a schema problem")
  func testSchemaProblem() {
    let schema = ParamSchema([
      ParamSpec(id: "t", title: "T", level: .simple, text: "abc", maxLength: 2)
    ])
    #expect(schema.problems == ["t: default longer than 2"])
  }

  @Test(
    "a pipeline step: the injected tool runs; without it, the step is refused",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testPipelineHostTool() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let registry = try ProcessRegistry([PlateSolveProcess.self])
    let image = AstroImage(
      width: 2, height: 1, planes: [[0.1, 0.2]], metadata: ImageMetadata(rowOrder: .topDown))
    let stats = StudioSession.stats(of: image)
    let bundle = PipelineBundle(stats: stats, layers: ["RGB": image], layerStats: ["RGB": stats])
    let pipeline = Pipeline(
      name: "solve",
      steps: [
        PipelineStep(
          recipe: Recipe(
            processID: PlateSolveProcess.id, params: ParamSet(schema: PlateSolveProcess.schema)))
      ])
    await #expect(throws: PipelineError.toolMissing(PlateSolveProcess.id)) {
      _ = try await PipelineRunner(registry: registry, device: device, batch: [:]).replay(
        pipeline, on: image, in: try ScratchDirectory.url.appendingPathComponent("a"),
        bundle: bundle)
    }
    let tool = PipelineRunner.BatchProcess(schema: PlateSolveProcess.schema) { input, _, _ in
      AstroImage(
        width: input.width, height: input.height, planes: [[0.5, 0.5]], metadata: input.metadata)
    }
    let replay = try await PipelineRunner(
      registry: registry, device: device, batch: [PlateSolveProcess.id: tool]
    ).replay(
      pipeline, on: image, in: try ScratchDirectory.url.appendingPathComponent("b"), bundle: bundle)
    #expect(replay.history.current.planes == [[0.5, 0.5]], "the tool's result, not the preview")
  }
}

extension PlateSolveSchemaTests {
  @Test("a pipeline names a host-tool step without its tool before running")
  func testStepProblemWithoutTool() throws {
    let registry = try ProcessRegistry([PlateSolveProcess.self])
    let pipeline = Pipeline(
      name: "solve",
      steps: [
        PipelineStep(
          recipe: Recipe(
            processID: PlateSolveProcess.id, params: ParamSet(schema: PlateSolveProcess.schema)))
      ])
    #expect(
      pipeline.stepProblems(registry: registry, present: [.color])
        == [["runs a host tool: apply it in the Studio"]])
    #expect(
      pipeline.stepProblems(registry: registry, batch: [PlateSolveProcess.id], present: [.color])
        == [[]])
  }
}
