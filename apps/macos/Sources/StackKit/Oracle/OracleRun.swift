/// `run.json`: the legacy run result, normalized (volatile keys dropped, placeholders in paths).
///
/// Only the fields the port compares are decoded; the file keeps everything else.
package struct OracleRun: Decodable, Sendable {
  /// One stacked (or synthesized) channel.
  package struct Channel: Decodable, Sendable {
    /// The OBJECT the channel belongs to.
    package let object: String
    /// The channel's filter (`L`, `RGB`, `RGB-dualband`, `Ha`…).
    package let filter: String
    /// Light frames the channel started with.
    package let inputFrames: Int
    /// Frames that went into the stack.
    package let stackedFrames: Int
    /// The channel master, when one was written.
    package let outputPath: String?
    /// True for a channel separated from another channel's master (synthetic Hα/OIII).
    @OmittedFalse package var synthesized: Bool
  }

  /// The OBJECT of the run.
  package let object: String?
  /// The capture night every channel was registered onto (multi-night runs only).
  package let anchorNight: String?
  /// Calibration masters of the run.
  package let masters: [OracleMaster]
  /// The channels, in run order.
  package let channels: [Channel]
  /// Run-level warnings.
  package let warnings: [String]?
}
