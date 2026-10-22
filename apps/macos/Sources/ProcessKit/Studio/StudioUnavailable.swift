/// Why a process cannot be the Studio's next step: shown on the greyed process, never enforced
/// behind the user's back (R2).
package enum StudioUnavailable: Equatable, Sendable {
  /// Layers the process reads are missing (no StarNet step yet, no emission layer…).
  case missing([LayerRole])
  /// A linear process after the stretch.
  case linearAfterStretch
  /// A host-tool process whose tool is not installed (card 0093): greyed, Apply refused.
  case toolMissing
}
