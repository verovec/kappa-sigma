package import Foundation
package import StackKit

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
    let cache = remoteFrameCache
    let needed = queued.compactMap {
      try? ScratchEstimate($0, settings: settings, cache: cache).bytes
    }.max()
    guard let needed, needed > 0 else { return nil }
    let folder = runs.scratch
    return ScratchBudget(neededBytes: needed, roomBytes: runs.room(folder), folder: folder)
  }

  /// Where this project's bucket frames are kept between runs (card 0191): a folder of its own
  /// under the scratch folder, `nil` for a project not saved yet.
  ///
  /// Beside the runs' work folders, never in the package (nothing pixel-shaped travels with a
  /// project) nor in a capture folder (R7).
  package var remoteFrameCache: RemoteFrameCache? {
    folder().map { RemoteFrameCache(project: $0, scratch: runs.scratch) }
  }
}

nonisolated extension RunRequestPlan {
  /// Refuses the run of `inventory` when its estimate exceeds the room left in `folder`.
  ///
  /// The refusal is `PreprocessError.scratchFull`; a plan the engine refuses is left to the run,
  /// which names its own reason. Frames the project already keeps (card 0191) cost nothing.
  package func checkScratch(_ inventory: Inventory, folder: URL, room: @Sendable (URL) -> Int64?)
    throws
  {
    guard let estimate = try? ScratchEstimate(inventory, settings: settings, cache: cache)
    else { return }
    try estimate.check(room: room(folder), folder: folder)
  }
}
