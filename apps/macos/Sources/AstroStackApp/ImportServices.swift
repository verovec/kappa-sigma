/// The planner and the master services of one Import sheet, over one library index.
package nonisolated struct ImportServices: Sendable {
  package var planning: ImportViewModel.ProgressPlanning
  package var masters: MasterServices?

  /// Services from their parts; `planning` reports the scan's progress.
  package init(
    planning: @escaping ImportViewModel.ProgressPlanning, masters: MasterServices? = nil
  ) {
    self.planning = planning
    self.masters = masters
  }

  /// Services whose planning reports no progress.
  package init(planning: @escaping ImportViewModel.Planning, masters: MasterServices? = nil) {
    self.init(planning: ImportViewModel.reporting(planning), masters: masters)
  }
}
