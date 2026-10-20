/// `calibration.json`: the masters each channel (and each night group) was calibrated with.
package struct OracleCalibration: Decodable, Sendable {
  /// The masters picked for one channel, with the engine's notes.
  package struct Selection: Decodable, Sendable {
    /// The dark master, if any.
    package let dark: OracleMaster?
    /// The flat master, if any.
    package let flat: OracleMaster?
    /// The bias master, if any.
    package let bias: OracleMaster?
    /// Why each master was chosen or missing.
    package let notes: [String]?
    /// True when the dark is scaled to the lights' exposure (`calibrate -opt`): a verdict the
    /// user must see and can veto (R2).
    @OmittedFalse package var darkOptimize: Bool
  }

  /// The masters of one night group of a multi-night channel.
  package struct Group: Decodable, Sendable {
    /// Capture night (`YYYY-MM-DD`).
    package let session: String?
    /// Lights in the group.
    package let frames: Int
    /// Dark master path.
    package let dark: String?
    /// Flat master path.
    package let flat: String?
    /// Bias master path.
    package let bias: String?
    /// Where the flat came from (`run`, `library`, …).
    package let flatSource: String?
  }

  /// One channel's calibration.
  package struct Channel: Decodable, Sendable {
    /// OBJECT.
    package let object: String
    /// Filter.
    package let filter: String
    /// The channel-level selection.
    package let selection: Selection
    /// Per-night groups (multi-night runs only).
    package let groups: [Group]?
  }

  /// Every master of the run.
  package let masters: [OracleMaster]
  /// Channels, in run order.
  package let channels: [Channel]
}
