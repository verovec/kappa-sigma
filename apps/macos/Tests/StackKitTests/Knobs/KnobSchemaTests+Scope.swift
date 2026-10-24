import StackKit
import Testing

/// Card 0121: a knob one lane's stacker reads alone is `.lane` and may differ per lane; one the
/// shared canvas reads is `.run`, with why it is shared. The table is the audit: a new knob
/// without its row fails here.
extension KnobSchemaTests {
  static let scopes: [String: Knob.Scope] = [
    "stack_reject": .lane, "stack_reject_low": .lane, "stack_reject_high": .lane,
    "stack_weight": .lane, "stack_combine": .lane, "stack_norm": .lane,
    "stack_fast_norm": .lane, "stack_output_norm": .lane, "stack_rejection_maps": .lane,
    "stack_feather": .lane,
    "frame_review": .run(.breakpoints), "roundness_floor": .lane, "fwhm_sigma": .lane,
    "background_sigma": .lane, "star_count_frac": .lane, "roundness_sigma": .lane,
    "reject_trails": .lane,
    "reference_breakpoint": .run(.breakpoints), "trail_mask_k": .lane,
    "drop_wheel_transition": .lane,
    "trail_downsample": .lane,
    "register_2pass": .run(.registration),
    "edge_crop": .run(.framing), "coverage_crop": .run(.framing),
    "coverage_min_frac": .run(.framing),
    "photometric_normalisation": .run(.nights), "flatten_background": .run(.nights),
    "seam_offset_refit": .run(.nights), "seam_noise_eq": .run(.nights),
    "core_saturation_repair": .run(.nights),
    "background_degree": .run(.combine), "scnr": .run(.combine),
  ]

  @Test("every knob has a scope; a run-wide one says why it is shared (table pinned)")
  func testScopeAudit() {
    #expect(Set(KnobSchema.knobs.map(\.id)) == Set(Self.scopes.keys))
    for knob in KnobSchema.knobs {
      #expect(knob.scope == Self.scopes[knob.id], "\(knob.id)")
    }
    let reasons = Set(
      KnobSchema.knobs.compactMap { knob -> Knob.Shared? in
        if case .run(let why) = knob.scope { return why }
        return nil
      })
    #expect(reasons == Set(Knob.Shared.allCases), "every reason is used")
  }

  @Test(
    "a lane patch takes lane knobs only: a run-wide or unknown knob, or a bad value, is refused",
    arguments: [
      ("register_2pass", KnobValue.flag(true)), ("edge_crop", .flag(false)),
      ("no_such_knob", .number(1)), ("stack_reject_high", .number(99)),
    ])
  func testLanePatchRefusesRunKnobs(_ id: String, _ value: KnobValue) {
    #expect(throws: KnobError.self) {
      try KnobSchema.validateLane(KnobPatch(values: [id: value]))
    }
  }

  @Test("a lane patch of lane knobs is accepted")
  func testLanePatchAccepted() throws {
    try KnobSchema.validateLane(
      KnobPatch(values: ["stack_reject": .choice("winsorized"), "trail_mask_k": .number(2)]))
  }
}
