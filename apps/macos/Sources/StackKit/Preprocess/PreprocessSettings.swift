/// The deep-sky preprocessing knobs this pipeline reads (the legacy `mode.Preset` fields).
///
/// The single-night path's fields; `init()` is the deepsky preset. Every value is applied as
/// shown (R2).
package struct PreprocessSettings: Equatable, Sendable {
  /// The frame-rejection rules.
  package var grading = Grader.Options()
  /// Pause each lane after grading so the user can veto the verdicts (card 0069, `frame_review`).
  ///
  /// Off, the run never waits and its scripts stay byte-identical.
  package var frameReview = false
  /// Drop a run's first frame when the filter wheel was still moving (`DropFilterWheelTransition`).
  package var dropWheelTransition = true
  /// Siril's two-pass registration elects the reference instead of frame 1 (`Register2Pass`).
  package var register2Pass = false
  /// Trim the ragged stacking edge off the colour-combine inputs (`EdgeCrop`).
  package var edgeCrop = true
  /// The light stack (`lightStack(wfwhm)`).
  package var stack = StackOptions.lights
  /// The trail probe's downsampled size (`trailDownsample`).
  package var trailDownsample = 512
  /// The cross-frame transient mask on the registered frames, in per-pixel σ above the median
  /// (`TrailMaskK`).
  ///
  /// 0 is off. Trails, cosmic rays and hot pixels are cleaned before the stack.
  package var trailMaskK = 3.0
  /// Background degree of the combine's and the neutralization's `subsky`.
  package var backgroundDegree = 1
  /// `rmgreen` type of the neutralization.
  package var scnr = 0
  /// Map every night onto the anchor night's photometric scale before the merge (`PhotomNorm`).
  package var photometricNormalisation = true
  /// Flatten each frame's own sky gradient before a multi-night registration (`FlattenBg`).
  package var flattenBackground = true
  /// Re-fit each night's sky offset on the overlap with the anchor night (`SeamOffsetRefit`).
  package var seamOffsetRefit = true
  /// Even out the noise depth where coverage changes, on the stacked master (`SeamNoiseEq`).
  package var seamNoiseEqualisation = true
  /// Repair sensor-saturated cores from unsaturated nights before the stack (`CoreSatMask`).
  package var coreSaturationRepair = true
  /// Cut the combine inputs to the field every channel covers (`CoverageCrop`).
  package var coverageCrop = true
  /// The fraction of frames a cell needs to count as covered (`CoverageMinFrac`).
  package var coverageMinimumFraction = 0.30
  /// Where the parity probes' `platesolve` looks (`"RA,DEC"`): stacked masters lose their
  /// pointing cards, so without it they rarely solve and the parity check is skipped (it says so).
  package var solveCoordinates: String?
  /// The calibration suggestions the user unchecked on the Import sheet (`calib_exclude`, by
  /// `CalibrationMatcher.suggestionID`): those roles are not applied, as the plan showed.
  package var calibrationExcluded: [String] = []
  /// Apply the masters even where camera, temperature or filter set disagree
  /// (`force_calibration_frames`), as the plan showed.
  package var forceCalibration = false

  /// The deepsky preset, with optional overrides.
  package init(dropWheelTransition: Bool = true, register2Pass: Bool = false) {
    self.dropWheelTransition = dropWheelTransition
    self.register2Pass = register2Pass
  }

  /// The legacy preset of `mode` (`mode.Preset`): nebula grades more leniently (faint, diffuse
  /// targets) and models the sky with a degree-2 polynomial.
  package static func preset(_ mode: PreprocessRequest.Mode) -> Self {
    var settings = Self()
    guard mode == .nebula else { return settings }
    settings.grading.roundnessFloor = 0.50
    settings.grading.roundnessSigma = 3.0
    settings.grading.fwhmSigma = 3.0
    settings.grading.backgroundSigma = 3.0
    settings.grading.starCountFraction = 0.4
    settings.backgroundDegree = 2
    return settings
  }
}
