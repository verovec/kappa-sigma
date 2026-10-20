/// `selection.json`: which frames each channel kept and rejected, and the scripts' `unselect`s.
package struct OracleSelection: Decodable, Sendable {
  /// A frame the grading rejected.
  package struct Rejected: Decodable, Sendable {
    /// Normalized frame path.
    package let path: String
    /// The engine's reason, shown to the user (R2: every verdict is visible).
    package let reason: String
  }

  /// Per-night counts of a multi-night channel.
  package struct Group: Decodable, Sendable {
    /// Capture night.
    package let session: String?
    /// Frames stacked from the night.
    package let stackedFrames: Int
    /// Frames rejected from the night.
    package let rejectedFrames: Int
  }

  /// One channel's selection.
  package struct Channel: Decodable, Sendable {
    /// OBJECT.
    package let object: String
    /// Filter.
    package let filter: String
    /// True for a synthesized channel (no frames of its own).
    @OmittedFalse package var synthesized: Bool
    /// Lights the channel started with.
    package let inputFrames: Int
    /// Frames that went into the stack.
    package let stackedFrames: Int
    /// Graded frames that were kept.
    package let kept: [String]
    /// Graded frames that were rejected, with reasons.
    package let rejected: [Rejected]
    /// Per-night counts (multi-night runs only).
    package let groups: [Group]?
  }

  /// Channels, in run order.
  package let channels: [Channel]
  /// Every `unselect` the stack scripts ran (registered-space drops not in run.json).
  package let unselect: [OracleScriptCommand]
}
