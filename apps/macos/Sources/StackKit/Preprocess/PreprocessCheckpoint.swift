/// Where a paused run stands (card 0097).
///
/// Its lanes stacked (master and `LaneRecord` kept in the output folder) and those left. Continue
/// re-plans the request and skips the lanes whose record still matches it.
package struct PreprocessCheckpoint: Codable, Equatable, Sendable {
  package var runID: String
  /// The lanes stacked, in run order (a failed lane counts: its record says why).
  package var lanesDone: [String]
  /// The lanes the run has not started, in run order.
  package var lanesLeft: [String]

  /// A checkpoint of `runID`.
  package init(runID: String, lanesDone: [String], lanesLeft: [String]) {
    self.runID = runID
    self.lanesDone = lanesDone
    self.lanesLeft = lanesLeft
  }

  private enum CodingKeys: String, CodingKey {
    case runID = "run_id"
    case lanesDone = "lanes_done"
    case lanesLeft = "lanes_left"
  }
}
