/// The merged cross-night registration, inspected before it is applied (`reviewMergedRegistration`).
///
/// The anchor night's middle frame is pinned (`setref`) so the canvas is the anchor's full field
/// (a user pin, card 0096, moves the canvas to the pinned frame's field); a frame whose footprint
/// overlaps that field under 20% is a false star match and leaves the stack; each night's
/// median rotation and overlap is recorded.
package struct RegistrationReview: Equatable, Sendable {
  /// One night's telemetry.
  package struct Group: Equatable, Sendable {
    package var registered = 0
    package var absurd = 0
    package var rotationDegrees: Double?
    package var overlapFraction: Double?
  }

  /// Under this overlap with the reference field, a transform is a false star match.
  static let absurdOverlap = 0.20

  /// 1-based frame to `setref`; 0 keeps Siril's reference.
  package var referenceIndex = 0
  /// 0-based frame → why it leaves the stack.
  package var preReject: [Int: String] = [:]
  package var groups: [Group]
  package var warnings: [String] = []
  /// Each kept frame's homography relative to the reference (frame → canvas), by 0-based index.
  package var frameHomographies: [Int: [Double]] = [:]

  /// A review that kept exactly these frames (what the refit and coverage read).
  package init(frameHomographies: [Int: [Double]], nights: Int) {
    groups = Array(repeating: Group(), count: nights)
    self.frameHomographies = frameHomographies
  }

  /// Reviews `sequence` over the nights' `spans`, `anchor` being the anchor night's span index;
  /// `width`/`height` are the frames' size (0: the gate is skipped, with a warning). `pinned`
  /// (card 0096, 1-based) replaces the anchor night's election when that frame registered; a
  /// pin on a dropped frame is a warning and the election stands.
  package init(
    _ sequence: SirilSequence, spans: [Range<Int>], anchor: Int, width: Int, height: Int,
    pinned: Int? = nil
  ) {
    groups = Array(repeating: Group(), count: spans.count)
    let metrics = sequence.metrics
    let registered = Self.registered(metrics)
    // The anchor night's election only: without one, Siril's own reference is read for the
    // transforms but never `setref` (`referenceIndex` stays 0, as recorded).
    var reference =
      anchor >= 0 && anchor < spans.count ? Self.anchorReference(spans[anchor], registered) : nil
    if let pinned {
      if registered(pinned - 1) {
        reference = pinned - 1
      } else {
        warnings.append(
          "pinned reference frame \(pinned) did not register — keeping the elected frame")
      }
    }
    if let reference {
      referenceIndex = reference + 1
    } else {
      warnings.append("no anchor-night frame registered — keeping Siril's own reference frame")
      guard registered(sequence.reference) else { return }
      reference = sequence.reference
    }
    guard width > 0, height > 0, let reference else {
      warnings.append("frame dimensions unreadable — transform review skipped")
      return
    }
    review(
      metrics, spans: spans, reference: reference, width: Double(width), height: Double(height))
  }

  /// A frame registered with a transform: the only kind the review and a pin can use.
  package static func registered(_ metrics: [SirilSequence.Metric]) -> (Int) -> Bool {
    { index in
      index >= 0 && index < metrics.count && metrics[index].fwhm > 0
        && metrics[index].hasHomography
    }
  }

  /// The frame the review registers onto without a pin, as `FrameGrade.index` (1-based): the
  /// anchor night's election, else Siril's own reference when it registered (what the review
  /// falls back to); nil when neither exists (card 0096 shows it).
  package static func election(_ sequence: SirilSequence, spans: [Range<Int>], anchor: Int)
    -> Int?
  {
    let registered = registered(sequence.metrics)
    if anchor >= 0, anchor < spans.count,
      let elected = anchorReference(spans[anchor], registered)
    {
      return elected + 1
    }
    return sequence.referenceIndex.flatMap { registered($0 - 1) ? $0 : nil }
  }

  /// The anchor span's middle frame when it registered, else the nearest registered one,
  /// middle-out, the later side first (`pickAnchorRef`).
  static func anchorReference(_ span: Range<Int>, _ registered: (Int) -> Bool) -> Int? {
    guard !span.isEmpty else { return nil }
    let middle = span.lowerBound + span.count / 2
    for offset in 0... {
      let (low, high) = (middle - offset, middle + offset)
      if low < span.lowerBound && high >= span.upperBound { return nil }
      if high < span.upperBound && registered(high) { return high }
      if low >= span.lowerBound && registered(low) { return low }
    }
    return nil
  }

  private mutating func review(
    _ metrics: [SirilSequence.Metric], spans: [Range<Int>], reference: Int, width: Double,
    height: Double
  ) {
    let referenceH = metrics[reference].homography
    for (night, span) in spans.enumerated() {
      var (rotations, overlaps): ([Double], [Double]) = ([], [])
      for index in span where index < metrics.count {
        let metric = metrics[index]
        guard metric.fwhm > 0, metric.hasHomography else { continue }
        groups[night].registered += 1
        guard let relative = Homography.relative(referenceH, metric.homography) else { continue }
        let overlap = Homography.footprintOverlap(relative, width: width, height: height)
        if overlap < Self.absurdOverlap {
          groups[night].absurd += 1
          preReject[index] =
            "absurd registration transform (\(Int((overlap * 100).rounded()))% overlap "
            + "with the reference field) — false star match"
          continue
        }
        rotations.append(Homography.rotationDegrees(relative))
        overlaps.append(overlap)
        frameHomographies[index] = relative
      }
      if !rotations.isEmpty {
        groups[night].rotationDegrees = PhotomStats.median(rotations)
        groups[night].overlapFraction = PhotomStats.median(overlaps)
      }
    }
  }
}
