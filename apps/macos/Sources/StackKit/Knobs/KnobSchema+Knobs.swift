// MARK: - The knobs, by area

extension KnobSchema {
  /// The light stack (`stack` clause): rejection, weighting, normalization, feathering.
  static let stack: [Knob] = [
    .choice(
      "stack_reject", .simple, StackOptions.Rejection.allCases.map(\.knobID),
      read: { $0.stack.rejection.knobID },
      write: { settings, id in
        if let rejection = StackOptions.Rejection(knobID: id) {
          settings.stack.rejection = rejection
        }
      }),
    // 0 takes the algorithm's own default (StackClause), the stored value stays as asked.
    .number("stack_reject_low", .simple, 0...10, \.stack.low),
    .number("stack_reject_high", .simple, 0...10, \.stack.high),
    .choice(
      "stack_weight", .simple, ["none", "wfwhm", "noise", "nbstars", "nbstack"],
      read: { $0.stack.weight ?? "none" },
      write: { $0.stack.weight = $1 == "none" ? nil : $1 }),
    .choice(
      "stack_combine", .advanced, StackOptions.Combine.allCases.map(\.rawValue),
      read: { $0.stack.combine.rawValue },
      write: { settings, id in
        if let combine = StackOptions.Combine(rawValue: id) { settings.stack.combine = combine }
      }),
    .choice(
      "stack_norm", .advanced, StackOptions.Normalization.allCases.map(\.rawValue),
      read: { $0.stack.normalization.rawValue },
      write: { settings, id in
        if let norm = StackOptions.Normalization(rawValue: id) {
          settings.stack.normalization = norm
        }
      }),
    .flag("stack_fast_norm", .advanced, \.stack.fastNormalization),
    .flag("stack_output_norm", .advanced, \.stack.outputNormalization),
    .flag("stack_rejection_maps", .advanced, \.stack.rejectionMaps),
    .integer("stack_feather", .advanced, 0...512, \.stack.featherPx),
  ]

  /// Which registered frames are stacked (`Grader.Options`).
  static let grading: [Knob] = [
    .flag(frameReviewID, .simple, \.frameReview),
    .number("roundness_floor", .simple, 0.2...0.95, \.grading.roundnessFloor),
    .number("fwhm_sigma", .simple, 1...5, \.grading.fwhmSigma),
    .number("background_sigma", .simple, 1...5, \.grading.backgroundSigma),
    .number("star_count_frac", .simple, 0.1...1, \.grading.starCountFraction),
    .number("roundness_sigma", .advanced, 1...5, \.grading.roundnessSigma),
    .flag("reject_trails", .advanced, \.grading.rejectTrails),
  ]

  /// Registration, framing, the transient mask, several nights and the combine: run-wide but for
  /// the reference pin, the transient mask and the wheel-transition drop, which one lane reads.
  static let run: [Knob] = [
    .flag("register_2pass", .simple, \.register2Pass).shared(.registration),
    .flag(referenceBreakpointID, .advanced, \.referenceBreakpoint),
    .flag("edge_crop", .simple, \.edgeCrop).shared(.framing),
    .flag("coverage_crop", .simple, \.coverageCrop).shared(.framing),
    .number("trail_mask_k", .simple, 0...6, \.trailMaskK),
    .number("coverage_min_frac", .advanced, 0.05...0.9, \.coverageMinimumFraction)
      .shared(.framing),
    .flag("drop_wheel_transition", .advanced, \.dropWheelTransition),
    .integer("trail_downsample", .advanced, 128...2048, \.trailDownsample),
    .flag("photometric_normalisation", .advanced, \.photometricNormalisation).shared(.nights),
    .flag("flatten_background", .advanced, \.flattenBackground).shared(.nights),
    .flag("seam_offset_refit", .advanced, \.seamOffsetRefit).shared(.nights),
    .flag("seam_noise_eq", .advanced, \.seamNoiseEqualisation).shared(.nights),
    .flag("core_saturation_repair", .advanced, \.coreSaturationRepair).shared(.nights),
    .integer("background_degree", .advanced, 1...4, \.backgroundDegree).shared(.combine),
    // Siril `rmgreen` type: 0 average neutral, 1 maximum neutral, 2 maximum mask, 3 additive mask.
    .integer("scnr", .advanced, 0...3, \.scnr).shared(.combine),
  ]
}

extension StackOptions.Rejection {
  /// The knob id: Siril's token (`StackClause.algorithm`), plus `auto` and `none`.
  var knobID: String {
    StackClause.algorithm(self)?.token ?? (self == .auto ? "auto" : "none")
  }

  init?(knobID: String) {
    guard let match = Self.allCases.first(where: { $0.knobID == knobID }) else { return nil }
    self = match
  }
}
