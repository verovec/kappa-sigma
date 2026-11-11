package import FilterKit
package import Foundation
package import StackKit

/// Everything a run's request says before the scan answers: the folders it writes, the knobs as
/// the panel showed them, its pause gate, and the buckets its frames are read from (card 0154).
///
/// Fixed when Run is pressed, so the request the run receives is the one the stage showed (R2);
/// the inventory and the library are the planner's, handed over at the last moment.
package nonisolated struct RunRequestPlan: Sendable {
  package var output: URL
  package var work: URL
  package var runID: String
  package var mode: PreprocessRequest.Mode
  package var settings: PreprocessSettings
  /// Lets the stage ask the run to stop after the lane it is in (card 0097).
  package var gate: PauseGate
  /// A Continue of a paused run (card 0097).
  package var resuming: Bool
  /// The buckets the run reads frames from (card 0154); empty for a capture of this Mac.
  package var stores: [RemoteObjectStore]
  /// The lane-scoped knobs a split run takes (card 0121).
  package var laneKnobs: [FilterSet: KnobPatch]
  /// Where the frames the run downloads from its buckets are kept between runs (card 0191);
  /// `nil` for a run that downloads into its lanes.
  package var cache: RemoteFrameCache?

  /// A plan of the run's own choices.
  package init(
    output: URL, work: URL, runID: String, mode: PreprocessRequest.Mode,
    settings: PreprocessSettings, gate: PauseGate, resuming: Bool,
    stores: [RemoteObjectStore] = [], laneKnobs: [FilterSet: KnobPatch] = [:],
    cache: RemoteFrameCache? = nil
  ) {
    self.cache = cache
    self.output = output
    self.work = work
    self.runID = runID
    self.mode = mode
    self.settings = settings
    self.gate = gate
    self.resuming = resuming
    self.stores = stores
    self.laneKnobs = laneKnobs
  }

  /// The request for `inventory` against `library`; a lane knob the schema refuses throws, as it
  /// does on the panel.
  package func request(inventory: Inventory, library: [CalibrationMaster]) throws
    -> PreprocessRequest
  {
    var request = PreprocessRequest(
      inventory: inventory, output: output, work: work, runID: runID, mode: mode,
      settings: settings, library: library)
    request.pause = gate
    request.resuming = resuming
    request.remoteStores = stores
    request.remoteCache = cache
    for (lane, patch) in laneKnobs {
      try request.overrideLane(lane, with: KnobSchema.laneAccepted(patch).accepted)
    }
    return request
  }
}
