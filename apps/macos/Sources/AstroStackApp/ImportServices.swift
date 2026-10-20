/// The planner and the master services of one Import sheet, over one library index.
package nonisolated struct ImportServices: Sendable {
  package var planning: ImportViewModel.Planning
  package var masters: MasterServices?

  /// Services from their parts.
  package init(planning: @escaping ImportViewModel.Planning, masters: MasterServices? = nil) {
    self.planning = planning
    self.masters = masters
  }
}
