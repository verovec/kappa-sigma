import Foundation
import HelpKit
import Metal
import ProcessKit
import Testing

/// A process declaring `.px` parameters without `previewExactOnlyAt1to1`: refused by the registry.
struct UnflaggedPixelProcess: ImageProcess {
  static let id = "unflagged-px"
  static let title = "Unflagged"
  static let stage = ProcessStage.nonlinear
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {}
}

/// Needs the starless and stars layers.
struct StarLayerProcess: ImageProcess {
  static let id = "star-layer"
  static let title = "Star layer"
  static let stage = ProcessStage.nonlinear
  static let requires: [LayerRole] = [.starless, .stars]
  static let schema = ParamSchema([])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {}
}

/// Help cards for the gate's failure cases (fixture texts only).
struct WordyGain: ImageProcess {
  static let id = "wordy-gain"
  static let title = "Wordy"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {}
}

struct FrenchOnlyGain: ImageProcess {
  static let id = "french-only-gain"
  static let title = "French only"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {}
}

@Suite("Process schema: stage, required layers, preview flag; registry; help coverage")
struct ProcessSchemaTests {
  @Test(
    "a .px parameter needs previewExactOnlyAt1to1; a missing layer gives the reason",
    arguments: [
      ("dummy-gain", Set<LayerRole>(), [String](), String?.none),
      ("unflagged-px", [], ["has .px parameters (shift): declare previewExactOnlyAt1to1"], nil),
      ("star-layer", [.starless, .stars], [], nil),
      ("star-layer", [.starless], [], "needs a stars layer"),
      ("star-layer", [.color], [], "needs a starless layer and a stars layer"),
    ] as [(String, Set<LayerRole>, [String], String?)])
  func testStageRequiresAndPreviewFlag(
    id: String, present: Set<LayerRole>, problems: [String], reason: String?
  ) throws {
    let types: [any ImageProcess.Type] = [DummyGain.self, UnflaggedPixelProcess.self, StarLayerProcess.self]
    let type = try #require(types.first { $0.id == id })
    #expect(ProcessRegistry.problems(of: type) == problems)
    #expect(LayerRole.unavailableReason(requires: type.requires, present: present) == reason)
    #expect(type.stage == (id == "dummy-gain" ? .any : .nonlinear))
  }

  @Test("the registry refuses an invalid process or a duplicate id, and finds by id")
  func testRegistry() throws {
    let registry = try ProcessRegistry([DummyGain.self, StarLayerProcess.self])
    #expect(registry.type(id: "star-layer") == StarLayerProcess.self)
    #expect(registry.ids == ["dummy-gain", "star-layer"])
    #expect(throws: RegistryError.invalid(id: "unflagged-px", problems: [
      "has .px parameters (shift): declare previewExactOnlyAt1to1",
    ])) { try ProcessRegistry([UnflaggedPixelProcess.self]) }
    #expect(throws: RegistryError.duplicate(id: "dummy-gain")) {
      try ProcessRegistry([DummyGain.self, DummyGain.self])
    }
  }

  static var fixtureHelp: HelpIndex {
    get throws {
      let root = try #require(Bundle.module.url(forResource: "Fixtures/Help", withExtension: nil))
      return HelpIndex(root: root)
    }
  }

  @Test("help gate: DummyGain ships fr+en cards; a missing locale or a 6-line card fails")
  func testEveryProcessHasCardFrEn() throws {
    let help = try Self.fixtureHelp
    #expect(help.coverageProblems(processIDs: [DummyGain.id]).isEmpty)
    #expect(help.card(process: DummyGain.id, locale: "en")?.hasPrefix("Multiplies") == true)
    #expect(help.coverageProblems(processIDs: [FrenchOnlyGain.id]) == [
      "french-only-gain: no en card"
    ])
    #expect(help.coverageProblems(processIDs: [WordyGain.id]) == [
      "wordy-gain (fr): 6 lines > 5"
    ])
  }

  @Test("a card over 90 words fails the gate", arguments: [(90, true), (91, false)])
  func testCardWordLimit(words: Int, passes: Bool) {
    let text = Array(repeating: "mot", count: words).joined(separator: " ")
    #expect(HelpIndex.cardProblems(text).isEmpty == passes)
  }

  @Test("the shipped registry passes the gate against the shipped help")
  func testShippedRegistryHasHelp() {
    let registry = ProcessRegistry.standard
    #expect(HelpIndex.bundled.coverageProblems(processIDs: registry.ids).isEmpty)
  }
}
