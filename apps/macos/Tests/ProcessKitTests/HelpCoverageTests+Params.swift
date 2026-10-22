import Foundation
import HelpKit
import Metal
import ProcessKit
import Testing

/// A registered process whose parameter has no definition in any locale: the gate must name it.
struct UndocumentedKnob: ImageProcess {
  static let id = "undocumented-knob"
  static let title = "Undocumented knob"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([
    ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...2)
  ])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {
  }
}

extension HelpCoverageTests {
  /// Card 0086: every parameter of every registered process has a one-line definition in French
  /// and English (`params.json`, `<process>.<param>`), none is stale, and the fixture process
  /// with an undocumented parameter fails the gate by name.
  @Test("testEveryProcessParamHasDocFrEn")
  func testEveryProcessParamHasDocFrEn() throws {
    let registry = try ProcessRegistry.standard()
    let ids = registry.types.flatMap { type in type.schema.specs.map { "\(type.id).\($0.id)" } }
    #expect(ids.count >= 90)
    let help = HelpIndex.bundled
    #expect(help.paramProblems(ids: ids) == [])
    for locale in HelpIndex.locales {
      #expect(help.params.stale(ids: ids, locale: locale) == [])
      let doc = try #require(
        help.paramDoc(process: "stretch", param: "targetBackground", locale: locale))
      #expect(!doc.isEmpty)
    }
    #expect(help.paramDoc(process: "stretch", param: "nope", locale: "en") == nil)

    let fixtures = try ProcessRegistry([DummyGain.self, UndocumentedKnob.self])
    let fixtureIDs = fixtures.types.flatMap { type in
      type.schema.specs.map { "\(type.id).\($0.id)" }
    }
    #expect(
      try ProcessSchemaTests.fixtureHelp.paramProblems(ids: fixtureIDs) == [
        "undocumented-knob.gain: no fr definition", "undocumented-knob.gain: no en definition",
      ])
  }
}
