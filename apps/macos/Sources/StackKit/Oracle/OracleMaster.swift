/// A calibration master the legacy run built or picked (`calib.Master`).
package struct OracleMaster: Decodable, Equatable, Sendable {
  /// `BIAS`, `DARK` or `FLAT`.
  package let type: String
  /// The flat's filter, when filter-specific.
  package let filter: String?
  /// Exposure of the frames the master was built from, in milliseconds.
  package let exposureMs: Int
  /// Camera gain.
  package let gain: Int
  /// Camera offset.
  package let offset: Int
  /// Sensor temperature in milli-degrees Celsius, `nil` when the frames carried none.
  package var temperatureMilliC: Int? { hasTemp ? tempMilliC : nil }
  // Go always writes temp_milli_c (0 when unknown); has_temp says whether it means anything.
  private let tempMilliC: Int
  private let hasTemp: Bool
  /// Binning.
  package let bin: Int
  /// Number of frames combined.
  package let frameCount: Int?
  /// The master's normalized path.
  package let path: String
}
