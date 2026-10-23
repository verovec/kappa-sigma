package import Foundation

/// One preprocessing run of a single night: what to stack, how, and where it lands.
package struct PreprocessRequest: Sendable {
  /// The legacy presets this path knows (`PreprocessSettings.preset`).
  package enum Mode: String, Codable, Sendable {
    case deepsky, nebula
  }

  /// The scanned capture, overrides already applied (0046).
  package var inventory: Inventory
  package var mode: Mode
  /// The knobs, as shown (R2): the preset of `mode` unless the request carries its own.
  package var settings: PreprocessSettings
  /// The calibration library (0047): reused only when its `.sig` proves the same frames.
  package var library: [CalibrationMaster]
  /// The run's output folder inside the project: masters, aligned, trims, `bundle.json`.
  package var output: URL
  /// Scratch for sequences and the run's own calibration masters.
  package var work: URL
  package var runID: String
  /// Asks the run to stop after the lane it is in (card 0097); nil: the run never pauses.
  package var pause: PauseGate?
  /// Continue of a paused run: every lane whose `LaneRecord` still matches is reused.
  package var resuming = false

  /// A request; without `settings`, the preset of `mode`.
  package init(
    inventory: Inventory, output: URL, work: URL, runID: String, mode: Mode = .deepsky,
    settings: PreprocessSettings? = nil, library: [CalibrationMaster] = []
  ) {
    self.inventory = inventory
    self.mode = mode
    var applied = settings ?? .preset(mode)
    // The plate-solve hint is a value the run shows: filled from the lights when not given.
    if applied.solveCoordinates == nil {
      applied.solveCoordinates = TargetCoordinates.from(inventory)
    }
    self.settings = applied
    self.library = library
    self.output = output
    self.work = work
    self.runID = runID
  }
}
