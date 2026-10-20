/// What signal-based filter detection found on unlabeled lights, for the UI to show and override
/// (`inspect.ChannelDetection`).
package struct ChannelDetection: Equatable, Sendable {
  /// The cyclic wheel order assumed.
  package var order: [String]
  /// The weakest group's confidence.
  package var overallConfidence = 0.0
  package var runs: [DetectedRun] = []
}

/// One contiguous same-filter capture block found by detection.
package struct DetectedRun: Equatable, Sendable {
  package var filter: String
  package var count: Int
  package var confidence: Double
  package var firstFrame = ""
  package var lastFrame = ""
  /// Frames of the run flagged as taken while the wheel was still moving.
  package var wheelTransitions = 0
}
