/// `registration.json`: per-night geometry, pre-rejected frames and the scripts' `setref`s.
package struct OracleRegistration: Decodable, Sendable {
  /// One night group's registration onto the anchor canvas.
  package struct Group: Decodable, Sendable {
    /// Capture night.
    package let session: String?
    /// Measured field rotation in degrees.
    package let rotationDeg: Double?
    /// Fraction of the anchor canvas the group overlaps.
    package let overlapFrac: Double?
    /// True when the group was mirrored to match the anchor.
    @OmittedFalse package var parityFlipped: Bool
  }

  /// One channel's registration.
  package struct Channel: Decodable, Sendable {
    /// OBJECT.
    package let object: String
    /// Filter.
    package let filter: String
    /// Frames the registration review dropped before stacking (absurd transforms).
    package let preRejected: [String]
    /// Per-night geometry (multi-night runs only).
    package let groups: [Group]?
  }

  /// The anchor night (multi-night runs only).
  package let anchorNight: String?
  /// Channels, in run order.
  package let channels: [Channel]
  /// Every `setref` the scripts ran: the reference frame of each registration.
  package let setref: [OracleScriptCommand]
}
