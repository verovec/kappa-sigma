/// The per-image data of a Siril `.seq` file (`grade.ParseSeq`): Siril's own selection (`I`
/// lines), the registration metrics (`R<layer>` lines) and the reference image (`S` line).
package struct SirilSequence: Equatable, Sendable {
  /// One frame's registration data; an unregistered frame has an all-zero line (`fwhm == 0`).
  package struct Metric: Equatable, Sendable {
    package var fwhm = 0.0
    package var wfwhm = 0.0
    package var roundness = 0.0
    package var quality = 0.0
    package var background = 0.0
    package var starCount = 0
    /// The 3×3 homography against the reference (row-major), when the line carries one.
    package var homography = [Double](repeating: 0, count: 9)
    package var hasHomography = false
    /// h02 and h12: the frame's translation in pixels.
    package var shiftX: Double { homography[2] }
    package var shiftY: Double { homography[5] }
  }

  package var metrics: [Metric] = []
  package var included: [Bool] = []
  /// 0-based reference image; -1 when unset.
  package var reference = -1

  /// The reference as a 1-based frame index, the one rule every reader uses.
  ///
  /// Nil when the `S` line is unset or names a frame the sequence does not have.
  package var referenceIndex: Int? {
    reference >= 0 && reference < metrics.count ? reference + 1 : nil
  }

  /// Parses `.seq` text.
  ///
  /// `R0 fwhm wfwhm roundness quality background nbstars H h00 … h22`
  /// (Siril 1.4.3); `nan`/`inf` read as 0, the dropped-frame sentinel.
  package init(parsing text: String) {
    for line in text.split(separator: "\n") {
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard let tag = fields.first else { continue }
      if tag == "S", fields.count >= 7 {
        reference = Int(Self.number(fields[6]))
      } else if tag == "I", fields.count >= 3 {
        included.append(fields[2] == "1")
      } else if tag.count >= 2, tag.first == "R", tag.dropFirst().first?.isASCIIDigit == true,
        fields.count >= 7
      {
        metrics.append(Self.metric(fields))
      }
    }
  }

  private static func metric(_ fields: [String]) -> Metric {
    var metric = Metric()
    metric.fwhm = number(fields[1])
    metric.wfwhm = number(fields[2])
    metric.roundness = number(fields[3])
    metric.quality = number(fields[4])
    metric.background = number(fields[5])
    metric.starCount = Int(number(fields[6]))
    if fields.count >= 17 && fields[7] == "H" {
      metric.homography = (0..<9).map { number(fields[8 + $0]) }
      metric.hasHomography = true
    }
    return metric
  }

  /// A field as a finite number, 0 otherwise.
  private static func number(_ text: String) -> Double {
    guard let value = Double(text), value.isFinite else { return 0 }
    return value
  }
}
