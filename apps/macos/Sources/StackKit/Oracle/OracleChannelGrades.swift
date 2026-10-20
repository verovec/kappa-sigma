/// One channel of `grades.json`: the per-frame metrics `grade.Metric` from Siril's sequence.
package struct OracleChannelGrades: Decodable, Sendable {
  /// One frame's grade.
  package struct Metric: Decodable, Sendable {
    /// 1-based position in the Siril sequence.
    package let index: Int
    /// Normalized frame path.
    package let path: String
    /// FWHM in pixels.
    package let fwhm: Double
    /// Weighted FWHM in pixels.
    package let wfwhm: Double
    /// Star roundness (0–1).
    package let roundness: Double
    /// Stars detected.
    package let starCount: Int
    /// Background level.
    package let background: Double
    /// Siril's quality score.
    package let quality: Double
    /// True when the grading rejected the frame.
    package let rejected: Bool
    /// Why, when rejected.
    package let rejectReason: String?
  }

  /// OBJECT.
  package let object: String
  /// Filter.
  package let filter: String
  /// Frame metrics, in sequence order.
  package let metrics: [Metric]
}
