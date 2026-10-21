import Foundation
import HelpKit
import Metal
import ProcessKit
import Testing

/// A registered process with no help card in any locale: the gate must name it.
struct UndocumentedGain: ImageProcess {
  static let id = "undocumented-gain"
  static let title = "Undocumented"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {
  }
}

/// Help coverage (card 0061): every registered process has a short card in French and English,
/// every value a shipped profile sets says why in both.
@Suite("Help coverage — a card per process, a why per profile value, fr and en")
struct HelpCoverageTests {
  @Test("every registered process has its fr+en card; one without a card fails the gate")
  func testEveryProcessHasCardFrEn() throws {
    let registry = try ProcessRegistry.standard()
    #expect(HelpIndex.bundled.coverageProblems(processIDs: registry.ids).isEmpty)
    for id in registry.ids {
      for locale in HelpIndex.locales {
        #expect(
          !HelpMarkdown.parse(HelpIndex.bundled.card(process: id, locale: locale) ?? "").isEmpty)
      }
    }

    let fixtures = try ProcessRegistry([DummyGain.self, UndocumentedGain.self, WordyGain.self])
    #expect(
      try ProcessSchemaTests.fixtureHelp.coverageProblems(processIDs: fixtures.ids).sorted() == [
        "undocumented-gain: no en card", "undocumented-gain: no fr card",
        "wordy-gain (fr): 6 lines > 5",
      ])
  }

  @Test("every value and knob a shipped profile sets has its why in fr and en")
  func testEveryProfileParamHasWhyFrEn() throws {
    let profiles = try ProfileLibrary.builtins(registry: ProcessRegistry.standard())
    #expect(!profiles.isEmpty)
    for profile in profiles {
      for step in profile.steps {
        for id in step.values.keys {
          let why = try #require(step.why[id], "\(profile.id) · \(step.recipe.processID).\(id)")
          #expect(!why.english.isEmpty && !why.french.isEmpty, "\(profile.id) · \(id)")
        }
      }
      for id in profile.preprocessing.knobs.keys {
        let why = try #require(profile.preprocessing.why[id], "\(profile.id) · knob \(id)")
        #expect(!why.english.isEmpty && !why.french.isEmpty, "\(profile.id) · knob \(id)")
      }
    }
  }
}
