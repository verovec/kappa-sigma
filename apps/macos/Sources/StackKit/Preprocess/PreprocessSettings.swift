/// The deep-sky preprocessing knobs this pipeline reads (the legacy `mode.Preset` fields).
///
/// The single-night path's fields; `init()` is the deepsky preset. Every value is applied as
/// shown (R2).
package struct PreprocessSettings: Equatable, Sendable {
  /// The frame-rejection rules.
  package var grading = Grader.Options()
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
  /// Background degree of the combine's and the neutralization's `subsky`.
  package var backgroundDegree = 1
  /// `rmgreen` type of the neutralization.
  package var scnr = 0

  /// The deepsky preset, with optional overrides.
  package init(dropWheelTransition: Bool = true, register2Pass: Bool = false) {
    self.dropWheelTransition = dropWheelTransition
    self.register2Pass = register2Pass
  }
}
