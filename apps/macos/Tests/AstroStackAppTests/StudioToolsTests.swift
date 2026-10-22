import AstroStackApp
import Foundation
import ProcessKit
import StackKit
import Testing

/// The panel's values as StackKit's background request (card 0092): each engine with its own
/// values as shown, the correction, the tool each engine needs, the reason a tool is refused.
@MainActor
@Suite("Studio tools — background extraction values to the engine, tool reasons")
struct StudioToolsTests {
  /// One row: the values set, the engine and correction StackKit receives, the tool needed.
  struct EngineCase: Sendable, CustomTestStringConvertible {
    let values: [String: ParamValue]
    let engine: BackgroundEngine
    let correction: BackgroundCorrection
    let tool: HostTool
    var testDescription: String { "\(engine)" }
  }

  @Test(
    "testEngineFromParams",
    arguments: [
      EngineCase(
        values: ["smoothing": .number(0.4), "correction": .choice("divide")],
        engine: .graxpert(smoothing: 0.4), correction: .divide, tool: .graxpert),
      EngineCase(
        values: [
          "engine": .choice("siril-rbf"), "rbfSmooth": .number(0.3), "samples": .number(41.6),
          "tolerance": .number(2), "dither": .flag(false),
        ],
        engine: .sirilRBF(smooth: 0.3, samples: 42, tolerance: 2, dither: false),
        correction: .subtract, tool: .siril),
      EngineCase(
        values: ["engine": .choice("siril-polynomial"), "degree": .number(3)],
        engine: .sirilPolynomial(degree: 3), correction: .subtract, tool: .siril),
    ])
  func testEngineFromParams(row: EngineCase) throws {
    var params = ParamSet(schema: BackgroundExtractionProcess.schema)
    for (id, value) in row.values { try params.set(id, value) }
    #expect(BackgroundEngine(params: params) == row.engine)
    #expect(BackgroundCorrection(params: params) == row.correction)
    #expect(
      BackgroundExtractionTool.host(for: BackgroundExtractionProcess.id, params: params) == row.tool
    )
    #expect(BackgroundExtractionTool.host(for: StretchProcess.id, params: params) == nil)
  }

  @Test("a missing or too old tool has its reason; a found one none")
  func testReasons() {
    var missing = StudioWorkspaceModel.reason(.graxpert, .missing(path: "/Applications/G.app"))
    missing?.locale = Locale(identifier: "fr")
    #expect(
      missing.map { String(localized: $0) } == "GraXpert n’est pas installé à /Applications/G.app.")
    #expect(StudioWorkspaceModel.reason(.siril, .tooOld(path: "/x", version: "1.2.0")) != nil)
    #expect(StudioWorkspaceModel.reason(.siril, .found(path: "/x", version: "1.4.4")) == nil)
  }
}
