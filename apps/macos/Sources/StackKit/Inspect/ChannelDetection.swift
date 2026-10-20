/// What signal-based filter detection found on unlabeled lights, for the UI to show and override
/// (`inspect.ChannelDetection`).
package struct ChannelDetection: Equatable, Sendable {
  /// The cyclic wheel order assumed.
  package var order: [String]
  /// The weakest group's confidence.
  package var overallConfidence = 0.0
  package var runs: [DetectedRun] = []
}
