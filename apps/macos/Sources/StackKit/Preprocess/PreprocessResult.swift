/// What a run produced (`Result`): its calibration masters, every channel's outcome, the crop,
/// the composite and the bundle, with all warnings.
package struct PreprocessResult: Equatable, Sendable {
  package var runID: String
  /// The calibration masters built or reused.
  package var masters: [CalibrationMaster] = []
  package var channels: [ChannelOutcome] = []
  /// The edge crop applied to the combine inputs, if any.
  package var crop: EdgeCropper.Crop?
  /// The common-coverage crop of a multi-night run, if any channel carries coverage.
  package var coverageCrop: CoverageCrop.Record?
  /// The linear colour composite, if the channels make one.
  package var combinedPath: String?
  package var bundle: LinearBundle?
  package var warnings: [String] = []
  /// The run's decisions that are not warnings: a dual-band split, each continuum scale.
  package var notes: [String] = []

  /// An empty result for `runID`.
  package init(runID: String) {
    self.runID = runID
  }
}
