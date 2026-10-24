/// What follows the stack of a split run (card 0121), chosen at Empilement and recorded on it:
/// the stacking is the same either way (one canvas); card 0122 picks the pipeline from it.
package enum StackProcessing: String, CaseIterable, Codable, Sendable {
  /// One flow: the bundle goes to the Studio as one history, as before E22.
  case single
  /// Broadband, Hα and OIII are processed apart before they are combined.
  case perChannel = "per_channel"
}
