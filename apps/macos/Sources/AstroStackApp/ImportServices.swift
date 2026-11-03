/// The planner and the master services of one Import sheet, over one library index.
package nonisolated struct ImportServices: Sendable {
  package var planning: ImportViewModel.ProgressPlanning
  package var masters: MasterServices?
  /// Scans a bucket prefix (card 0169); `nil` when the app offers no remote import.
  package var remotePlanning: ImportViewModel.RemotePlanning?
  /// Lists one level of a bucket for « Browse » (card 0169).
  package var browsing: ImportBucketModel.Browsing?

  /// Services from their parts; `planning` reports the scan's progress.
  package init(
    planning: @escaping ImportViewModel.ProgressPlanning, masters: MasterServices? = nil,
    remotePlanning: ImportViewModel.RemotePlanning? = nil,
    browsing: ImportBucketModel.Browsing? = nil
  ) {
    self.planning = planning
    self.masters = masters
    self.remotePlanning = remotePlanning
    self.browsing = browsing
  }

  /// Services whose planning reports no progress.
  package init(planning: @escaping ImportViewModel.Planning, masters: MasterServices? = nil) {
    self.init(planning: ImportViewModel.reporting(planning), masters: masters)
  }
}
