import Foundation
import StackKit
import Testing

/// The preprocessing knobs as one schema: every `PreprocessSettings` value the run reads, once,
/// with bounds and a level; the legacy deepsky surface accounted for key by key; a patch of
/// defaults changes nothing, so an untouched run stays byte-identical.
@Suite("KnobSchema — the preprocessing knobs, their levels and patches")
struct KnobSchemaTests {
  struct Legacy: Decodable {
    let preprocess: [String]
    let finishing: [String]
    let notPorted: [String: String]
    let swiftOnly: [String]
  }

  static func legacy() throws -> Legacy {
    let url = try #require(
      Bundle.module.url(
        forResource: "legacy-deepsky-knobs", withExtension: "json", subdirectory: "Fixtures/knobs"))
    return try JSONDecoder().decode(Legacy.self, from: Data(contentsOf: url))
  }

  @Test("every knob appears once with a level; the legacy surface is accounted for key by key")
  func testCompleteAndLevelled() throws {
    let ids = KnobSchema.knobs.map(\.id)
    #expect(Set(ids).count == ids.count, "no knob twice")
    let legacy = try Self.legacy()
    #expect(Set(ids) == Set(legacy.preprocess + legacy.swiftOnly))
    let classified = legacy.preprocess + legacy.finishing + Array(legacy.notPorted.keys)
    #expect(Set(classified).count == classified.count, "each legacy key in one class")
    #expect(Set(ids).isDisjoint(with: legacy.finishing), "finishing knobs belong to processes")
    #expect(legacy.notPorted.values.allSatisfy { !$0.isEmpty }, "a reason for each gap")
    #expect(KnobSchema.knobs.contains { $0.level == .simple })
    #expect(KnobSchema.knobs.contains { $0.level == .advanced })
  }

  @Test(
    "the card's simple set: rejection and sigmas, weighting, 2-pass, framing, grade thresholds")
  func testSimpleLevel() {
    let simple = Set(KnobSchema.knobs.filter { $0.level == .simple }.map(\.id))
    #expect(
      simple == [
        "stack_reject", "stack_reject_low", "stack_reject_high", "stack_weight", "register_2pass",
        "edge_crop", "coverage_crop", "roundness_floor", "fwhm_sigma", "background_sigma",
        "star_count_frac", "trail_mask_k",
        // Card 0069: the review breakpoint is a simple knob (R2: the veto is in plain view).
        "frame_review",
      ])
  }

  @Test(
    "every number has bounds holding its default in both presets; every choice holds its own",
    arguments: [PreprocessRequest.Mode.deepsky, .nebula])
  func testDefaultsInBounds(_ mode: PreprocessRequest.Mode) {
    let settings = PreprocessSettings.preset(mode)
    for knob in KnobSchema.knobs {
      let value = knob.value(in: settings)
      #expect(knob.accepts(value), "\(knob.id) = \(value) in \(mode)")
    }
  }

  @Test(
    "a patch of defaults leaves the settings equal: untouched runs stay byte-identical",
    arguments: [PreprocessRequest.Mode.deepsky, .nebula])
  func testDefaultsAreNoOp(_ mode: PreprocessRequest.Mode) throws {
    let preset = PreprocessSettings.preset(mode)
    let defaults = KnobPatch(
      values: Dictionary(
        uniqueKeysWithValues: KnobSchema.knobs.map { ($0.id, $0.value(in: preset)) }))
    #expect(try KnobSchema.apply(defaults, to: preset) == preset)
    #expect(KnobSchema.patch(from: preset, mode: mode).values.isEmpty)
    #expect(try KnobSchema.apply(KnobPatch(), to: preset) == preset)
  }

  struct Edit: Sendable, CustomTestStringConvertible {
    let id: String
    let value: KnobValue
    let check: @Sendable (PreprocessSettings) -> Bool
    var testDescription: String { "\(id) = \(value)" }
  }

  static let edits: [Edit] = [
    Edit(id: "fwhm_sigma", value: .number(3.5)) { $0.grading.fwhmSigma == 3.5 },
    Edit(id: "stack_reject", value: .choice("sigma")) { $0.stack.rejection == .sigma },
    Edit(id: "stack_weight", value: .choice("none")) { $0.stack.weight == nil },
    Edit(id: "stack_weight", value: .choice("noise")) { $0.stack.weight == "noise" },
    Edit(id: "register_2pass", value: .flag(true)) { $0.register2Pass },
    Edit(id: "stack_feather", value: .number(64)) { $0.stack.featherPx == 64 },
    Edit(id: "trail_mask_k", value: .number(0)) { $0.trailMaskK == 0 },
    Edit(id: "background_degree", value: .number(2)) { $0.backgroundDegree == 2 },
  ]

  @Test(
    "an edit lands on its setting, and the patch reads back only what changed", arguments: edits)
  func testEditApplies(_ edit: Edit) throws {
    let preset = PreprocessSettings.preset(.deepsky)
    let patch = KnobPatch(values: [edit.id: edit.value])
    let applied = try KnobSchema.apply(patch, to: preset)
    #expect(edit.check(applied))
    #expect(KnobSchema.patch(from: applied, mode: .deepsky) == patch)
  }

  @Test(
    "an unknown key, a value out of bounds, a fraction for an integer or a wrong kind is refused",
    arguments: [
      ("no_such_knob", KnobValue.number(1)), ("fwhm_sigma", .number(9)),
      ("background_degree", .number(1.5)), ("register_2pass", .number(1)),
      ("stack_reject", .choice("bogus")),
    ])
  func testInvalidPatchRefused(_ id: String, _ value: KnobValue) {
    #expect(throws: KnobError.self) {
      try KnobSchema.apply(KnobPatch(values: [id: value]), to: .preset(.deepsky))
    }
  }

  @Test("a patch is a flat JSON object under the legacy wire keys, and reads back unchanged")
  func testPatchWireFormat() throws {
    let patch = KnobPatch(values: [
      "fwhm_sigma": .number(3.5), "stack_reject": .choice("sigma"), "register_2pass": .flag(true),
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try #require(String(bytes: try encoder.encode(patch), encoding: .utf8))
    #expect(json == #"{"fwhm_sigma":3.5,"register_2pass":true,"stack_reject":"sigma"}"#)
    #expect(try JSONDecoder().decode(KnobPatch.self, from: Data(json.utf8)) == patch)
  }
}
