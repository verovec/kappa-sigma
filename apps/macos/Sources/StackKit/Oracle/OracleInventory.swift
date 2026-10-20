/// `inventory.json`: what `inspect.ScanMany` classified (frames, sessions, frame sets).
package struct OracleInventory: Decodable, Sendable {
  /// One classified frame.
  package struct Frame: Decodable, Sendable {
    /// Normalized path.
    package let path: String
    /// `LIGHT`, `DARK`, `FLAT`, `BIAS`, `DARKFLAT`.
    package let type: String
    /// OBJECT header, when present.
    package let object: String?
    /// FILTER header, when present.
    package let filter: String?
    /// Exposure in milliseconds.
    package let exposureMs: Int
    /// Camera gain.
    package let gain: Int
    /// Camera offset.
    package let offset: Int
    /// The capture night key (`YYYY-MM-DD`).
    package let session: String?
    /// Frame width in pixels.
    package let width: Int
    /// Frame height in pixels.
    package let height: Int
  }

  /// One frame set: frames sharing type, object, filter, exposure, gain, offset, temperature, bin.
  package struct FrameSet: Decodable, Sendable {
    /// Frames in the set.
    package let count: Int
    /// Summed exposure in milliseconds.
    package let totalIntegrationMs: Int
  }

  /// `mono` or `osc`.
  package let colorModel: String?
  /// Every classified frame.
  package let frames: [Frame]
  /// The frame sets.
  package let sets: [FrameSet]
}
