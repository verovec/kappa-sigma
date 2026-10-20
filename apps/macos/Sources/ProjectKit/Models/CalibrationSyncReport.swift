/// What a calibration-library sync changed in the index.
package struct CalibrationSyncReport: Equatable, Sendable {
  package var inserted: Int
  package var updated: Int
  package var deleted: Int

  /// The counts of a sync.
  package init(inserted: Int, updated: Int, deleted: Int) {
    self.inserted = inserted
    self.updated = updated
    self.deleted = deleted
  }
}
