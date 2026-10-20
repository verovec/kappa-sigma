package import Foundation

/// Stacks the calibration sets of a scan into masters through Siril (`BuildMasters`,
/// `BuildOrReuseMasters`): bias and dark-flats first (flats are calibrated with them), then darks,
/// then flats. A set that fails is a warning, never the end of the run.
package struct MasterBuilder: Sendable {
  /// Where a master is published.
  package enum Publish: Sendable {
    /// Straight to its name: a run's own masters folder, which nothing else reads meanwhile.
    case direct
    /// To a hidden `.tmp_<runID>_<name>` beside it, then renamed: the shared library, where
    /// another run must never read a half-written master.
    case atomic(runID: String)
  }

  /// What a build produced.
  package struct Result: Equatable, Sendable {
    package var masters: [CalibrationMaster] = []
    package var warnings: [String] = []
  }

  package var runner: SirilRunner
  package var recipes: MasterRecipes

  /// A builder running scripts through `runner` with the given recipes.
  package init(runner: SirilRunner, recipes: MasterRecipes = MasterRecipes()) {
    self.runner = runner
    self.recipes = recipes
  }

  /// Builds every calibration set of `inventory` into `folder`, reusing a `library` master
  /// only when its `.sig` proves it was stacked from the same frames.
  package func build(
    _ inventory: Inventory, into folder: URL, work: URL, publish: Publish = .direct,
    library: [CalibrationMaster] = []
  ) async throws -> Result {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var result = Result()
    var pool = library
    for type in MasterType.buildOrder {
      for set in inventory.sets where set.key.type == type.frameType {
        try Task.checkCancellation()
        if reuse(set, from: &pool, inventory: inventory, into: &result) { continue }
        do {
          var master = try await buildOne(set, built: pool, folder: folder, work: work, publish: publish, into: &result)
          master.stampFilterSet(of: set.key, in: inventory)
          pool.append(master)
          result.masters.append(master)
        } catch let error as CalibrationError {
          guard case .masterFailed(let name, let reason) = error else { throw error }
          result.warnings.append("stack master \(name): \(reason)")
        }
      }
    }
    return result
  }

  /// Reuses the library master of `set` when its pool is proven the same; otherwise drops it
  /// from the pool, so the matcher cannot pick it over the one about to be built.
  private func reuse(
    _ set: FrameSet, from pool: inout [CalibrationMaster], inventory: Inventory, into result: inout Result
  ) -> Bool {
    guard let index = pool.firstIndex(where: { $0.fromLibrary && $0.satisfies(set.key) }),
      FileManager.default.fileExists(atPath: pool[index].path)
    else { return false }
    let existing = pool[index]
    let type = existing.type.rawValue
    if PoolSignature.proves(master: existing.path, builtFrom: set.frames.map(\.path)) {
      var master = existing
      // The file lives in the library, but these are this run's own frames.
      master.fromLibrary = false
      master.stampFilterSet(of: set.key, in: inventory)
      pool[index] = master
      result.masters.append(master)
      result.warnings.append("reused library master \(type) (\(existing.frameCount) frames — same source frames)")
      return true
    }
    result.warnings.append(
      "rebuilding the \(type) master from this run's \(set.count) frame(s) — the library master "
        + "(\(existing.frameCount) frames) was built from different frames")
    pool.remove(at: index)
    return false
  }
}
