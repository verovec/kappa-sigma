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
