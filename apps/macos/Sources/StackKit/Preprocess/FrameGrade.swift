/// A registered sub and its keep/reject decision (`grade.Metric`); `Codable` for `grades.json`
/// (card 0069), snake_case keys set by the record's coder.
package struct FrameGrade: Codable, Equatable, Sendable {
  /// 1-based position in the Siril sequence.
  package var index: Int
  package var path: String
  package var fwhm = 0.0
  package var wfwhm = 0.0
  package var roundness = 0.0
  package var starCount = 0
  package var background = 0.0
  package var quality = 0.0
  package var trailDetected = false
  package var trailScore = 0.0
  package var rejected = false
  package var rejectReason = ""
  /// Registration translation against the reference, in pixels (dither/drift diagnostics).
  package var shiftX = 0.0
  package var shiftY = 0.0

  private enum CodingKeys: String, CodingKey {
    case index, path, fwhm, wfwhm, roundness, background, quality, rejected
    case starCount = "star_count"
    case trailDetected = "trail_detected"
    case trailScore = "trail_score"
    case rejectReason = "reject_reason"
    case shiftX = "shift_x"
    case shiftY = "shift_y"
  }

  /// A sub at `index` with no metrics yet.
  package init(index: Int, path: String) {
    self.index = index
    self.path = path
  }

  /// The sub's metrics as Siril measured them at registration.
  package init(index: Int, path: String, sequence metric: SirilSequence.Metric) {
    self.init(index: index, path: path)
    fwhm = metric.fwhm
    wfwhm = metric.wfwhm
    roundness = metric.roundness
    starCount = metric.starCount
    background = metric.background
    quality = metric.quality
    shiftX = metric.shiftX
    shiftY = metric.shiftY
  }
}
