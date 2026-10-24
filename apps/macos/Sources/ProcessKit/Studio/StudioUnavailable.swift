/// Why a process cannot be the Studio's next step: shown on the greyed process, never enforced
/// behind the user's back (R2).
package enum StudioUnavailable: Equatable, Sendable {
  /// Layers the process reads are missing (no StarNet step yet, no emission layer…).
  case missing([LayerRole])
  /// A linear process after the stretch.
  case linearAfterStretch
  /// A host-tool process whose tool is not installed (card 0093): greyed, Apply refused.
  case toolMissing
  /// A process reading the plate solution on a head without one (card 0094).
  case unsolved
  /// On a branch (card 0119): the process acts on the combined image (a stretch, a crop, a host
  /// tool…), not on one layer before the combination.
  case onCombinedImage
  /// On a branch: a host-tool process (colour calibration), which runs on the combined image only.
  case toolOnCombinedImage
  /// On a line branch (one plane): a colour process.
  case needsColourLayer
}
