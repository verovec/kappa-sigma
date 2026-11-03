/// Where a centred run of values lies in a FITS data unit (card 0167): what
/// `FITSFile.centerSample(maxCount:)` reads, located so a remote frame reads it by one range.
package struct FITSCenterRun: Equatable, Sendable {
  /// The index of its first value in the data unit.
  package let first: Int
  /// How many values it holds.
  package let count: Int
  /// The image's total value count (all planes).
  package let total: Int
  /// The bytes of one stored value.
  package let bytesPerValue: Int
}
