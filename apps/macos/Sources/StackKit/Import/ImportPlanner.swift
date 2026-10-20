/// Scans an `ImportRequest` and plans its calibration: the one entry the Import sheet calls.
package struct ImportPlanner: Sendable {
  package var builder: InventoryBuilder

  /// A planner scanning with `builder` (its time zone decides the nights).
  package init(builder: InventoryBuilder = InventoryBuilder()) {
    self.builder = builder
  }

  /// The plan of `request` against the library's indexed masters.
  package func plan(_ request: ImportRequest, library: [CalibrationMaster]) throws -> ImportPlan {
    let inventory = try builder.scan(paths: request.paths, overrides: request.overrides)
    return ImportPlan(inventory: inventory, library: library, request: request)
  }

  /// Whether going from `old` to `new` changes the scan; calibration choices only replan.
  package static func needsScan(from old: ImportRequest, to new: ImportRequest) -> Bool {
    old.paths != new.paths || old.overrides != new.overrides
  }

  /// Matches the scan and library of `plan` again under the calibration choices of `request`.
  ///
  /// Off the caller's actor: the matcher reads a header and the `.sig` files.
  @concurrent
  package static func replanned(_ plan: ImportPlan, request: ImportRequest) async -> ImportPlan {
    ImportPlan(inventory: plan.inventory, library: plan.library, request: request)
  }
}
