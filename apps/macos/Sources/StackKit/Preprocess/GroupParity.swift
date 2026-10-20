/// A night's mirror parity from a no-flip plate solve of its first calibrated frame
/// (`parityCache`).
///
/// The sign of det(CD). East-left (det < 0) is the convention every night is brought to; a mirrored
/// night is flipped with `mirrorx`, an unsolved one is left alone.
package enum GroupParity: Equatable, Sendable {
  /// det(CD) < 0: the target convention.
  case eastLeft
  /// det(CD) > 0: mirrored; its frames get `mirrorx`.
  case mirrored
  /// No solve, or a degenerate WCS: nothing is decided.
  case unknown

  /// The parity of a solve's det(CD) (nil: no usable WCS).
  package init(determinant: Double?) {
    guard let determinant else {
      self = .unknown
      return
    }
    self = determinant < 0 ? .eastLeft : .mirrored
  }

  /// Whether the night's frames are mirrored before co-registration.
  package var needsMirror: Bool { self == .mirrored }
}
