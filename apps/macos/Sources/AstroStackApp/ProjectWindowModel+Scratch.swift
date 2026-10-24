internal import Foundation
internal import StackKit

/// The scratch budget of the Stacking stage (card 0098): estimated before Run, refused before
/// Siril starts when the volume cannot hold it.
extension ProjectWindowModel {
  /// What the next run needs against the room left, from the last scan: the largest of the
  /// queued runs, with the panel's knobs; `nil` without a scan or a plannable run.
  package var scratchBudget: ScratchBudget? {
    guard let inventory = scan?.inventory else { return nil }
    let settings =
      (try? KnobSchema.apply(knobs.patch(for: knobs.mode), to: .preset(knobs.mode)))
      ?? .preset(knobs.mode)
    let queued = series.scopes.isEmpty ? [inventory] : series.scopes.map { inventory.scoped($0) }
    let needed = queued.compactMap { try? ScratchEstimate($0, settings: settings).bytes }.max()
    guard let needed, needed > 0 else { return nil }
    let folder = runs.scratch
    return ScratchBudget(neededBytes: needed, roomBytes: runs.room(folder), folder: folder)
  }

  /// Refuses the run of `inventory` when its estimate exceeds the room left in `folder`.
  ///
  /// The refusal is `PreprocessError.scratchFull`; a plan the engine refuses is left to the run,
  /// which names its own reason.
  nonisolated static func checkScratch(
    _ inventory: Inventory, settings: PreprocessSettings, folder: URL,
    room: @Sendable (URL) -> Int64?
  ) throws {
    guard let estimate = try? ScratchEstimate(inventory, settings: settings) else { return }
    try estimate.check(room: room(folder), folder: folder)
  }
}
