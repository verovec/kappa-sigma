/// A frame's parity against the run's convention (card 0096): what the parity probe did to its
/// night before the registration, shown beside each reference candidate.
package enum FrameParity: String, Codable, Equatable, Sendable {
  /// The night was not probed (a single night).
  case unprobed
  /// The night was already on the convention's side.
  case same
  /// The night's frames were mirrored on disk to match the convention.
  case mirrored
}
