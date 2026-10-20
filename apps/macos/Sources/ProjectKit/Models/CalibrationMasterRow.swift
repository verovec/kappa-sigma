/// One indexed master of the calibration library (`calibration_masters`, migration 0002).
///
/// ProjectKit stores what StackKit's library scan read; the folder stays the truth.
package struct CalibrationMasterRow: Equatable, Sendable {
  /// Absolute path of the `.fits` master: the natural key.
  package var path: String
  /// `BIAS`, `DARK`, `FLAT` or `DARKFLAT`.
  package var type: String
  package var filter = ""
  package var exposureMs = 0
  package var gain = 0
  package var offset = 0
  package var bin = 1
  package var tempMilliC = 0
  package var hasTemp = false
  /// Capture night of a per-night flat; `""` when night-blind.
  package var session = ""
  /// Non-default stacking recipe fingerprint; `""` for the default.
  package var recipe = ""
  /// Frames the master was stacked from (the `.sig` sidecar); 0 when unknown.
  package var frameCount = 0
  /// Pool signature from the `.sig` sidecar; `""` when absent.
  package var poolHash = ""
  /// Pixel size from the FITS header; 0 when unreadable.
  package var width = 0
  package var height = 0
  /// Size and modification time of the file at the last index: an unchanged file is skipped.
  package var fileBytes = 0
  package var fileMtimeMs: Int64 = 0

  /// A row for the master at `path`.
  package init(path: String, type: String) {
    self.path = path
    self.type = type
  }
}
