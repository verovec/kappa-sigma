import Foundation
import StackKit
import Testing

/// `RegistrationReview` and `Homography` are `reviewMergedRegistration` and
/// `grade/homography.go`: cases translated from `registration_test.go` and `homography_test.go`.
@Suite("RegistrationReview — the anchor reference, absurd transforms, per-night telemetry")
struct RegistrationReviewTests {
  /// A rotation by `degrees` about (cx, cy), then a translation: a real cross-night transform.
  static func rotation(_ degrees: Double, _ cx: Double, _ cy: Double, _ tx: Double, _ ty: Double)
    -> [Double]
  {
    let radians = degrees * .pi / 180
    let (cosine, sine) = (cos(radians), sin(radians))
    return [
      cosine, -sine, cx - cosine * cx + sine * cy + tx, sine, cosine,
      cy - sine * cx - cosine * cy + ty, 0, 0, 1,
    ]
  }

  static func line(_ h: [Double]) -> String {
    "R0 2.5 2.6 0.85 0.9 0.01 40 H " + h.map { "\($0)" }.joined(separator: " ")
  }

  static let unregistered = "R0 0 0 0 0 0 0 H 0 0 0 0 0 0 0 0 0"

  static func sequence(reference: Int, _ lines: [String]) -> SirilSequence {
    let header = "S 'light_' 1 \(lines.count) \(lines.count) 5 \(reference) 6 0 0 0\nL 1\n"
    let included = lines.indices.map { "I \($0 + 1) 1" }
    return SirilSequence(parsing: header + (included + lines).joined(separator: "\n"))
  }

  @Test("the anchor's middle frame is pinned; a 140° night is measured, not gated")
  func testAnchorsAndMeasures() throws {
    let (w, h) = (640.0, 480.0)
    var lines = [(4.0, -2.0), (6, 1), (-3, 5)].map {
      Self.line(Self.rotation(140, w / 2, h / 2, $0.0, $0.1))
    }
    lines += (0..<7).map { Self.line(Self.rotation(0, 0, 0, Double($0), -Double($0))) }
    let review = RegistrationReview(
      Self.sequence(reference: 6, lines), spans: [0..<3, 3..<10], anchor: 1, width: 640, height: 480
    )
    #expect(review.referenceIndex == 7 && review.warnings.isEmpty && review.preReject.isEmpty)
    let rotated = try #require(review.groups[0].rotationDegrees)
    let overlap = try #require(review.groups[0].overlapFraction)
    let anchorRotation = try #require(review.groups[1].rotationDegrees)
    #expect(abs(abs(rotated) - 140) <= 1 && overlap > 0.5 && abs(anchorRotation) <= 0.5)
    #expect(review.groups.map(\.registered) == [3, 7])
  }

  @Test("a false star match leaves the stack with its reason and the medians")
  func testGatesAbsurdTransform() throws {
    let lines = [(0.0, 0.0), (6000, -4000), (2, 1), (-1, 3), (1, -2)].map {
      Self.line(Self.rotation(0, 0, 0, $0.0, $0.1))
    }
    let review = RegistrationReview(
      Self.sequence(reference: 0, lines), spans: [0..<5], anchor: 0, width: 640, height: 480)
    #expect(review.referenceIndex == 3 && review.preReject.count == 1)
    #expect(review.preReject[1]?.contains("absurd registration transform") == true)
    let overlap = try #require(review.groups[0].overlapFraction)
    #expect(review.groups[0].absurd == 1 && overlap > 0.9)
  }

  @Test("an unregistered middle picks a neighbour; no anchor keeps Siril's; no size skips the gate")
  func testFallbacks() throws {
    let id = Self.line(Homography.identity)
    let middle = RegistrationReview(
      Self.sequence(reference: 0, [id, id, Self.unregistered, id, id]), spans: [0..<5], anchor: 0,
      width: 640, height: 480)
    #expect(middle.referenceIndex == 4 && middle.groups[0].registered == 4)

    let lost = RegistrationReview(
      Self.sequence(
        reference: 0,
        [id, Self.line(Self.rotation(0, 0, 0, 3, 1)), Self.unregistered, Self.unregistered]),
      spans: [0..<2, 2..<4], anchor: 1, width: 640, height: 480)
    #expect(
      lost.referenceIndex == 0
        && lost.warnings.first?.contains("no anchor-night frame registered") == true)
    #expect(lost.groups[0].overlapFraction != nil && lost.groups[1].registered == 0)

    let sizeless = RegistrationReview(
      Self.sequence(reference: 0, [id, id, id]), spans: [0..<3], anchor: 0, width: 0, height: 0)
    #expect(sizeless.referenceIndex == 2 && sizeless.preReject.isEmpty)
    #expect(sizeless.warnings.first?.contains("frame dimensions unreadable") == true)
  }

  @Test("homographies: re-referencing, footprint overlap, rotation")
  func testHomography() throws {
    let h = Self.rotation(30, 100, 80, 5, -3)
    let rel = try #require(Homography.relative(Homography.identity, h))
    #expect(zip(rel, h).allSatisfy { abs($0 - $1) <= 1e-9 })
    let selfRel = try #require(
      Homography.relative(
        Self.rotation(140, 320, 240, 40, 25), Self.rotation(140, 320, 240, 40, 25)))
    #expect(zip(selfRel, Homography.identity).allSatisfy { abs($0 - $1) <= 1e-9 })
    #expect(Homography.relative([Double](repeating: 0, count: 9), Homography.identity) == nil)
    let overlaps: [([Double], ClosedRange<Double>)] = [
      (Homography.identity, 0.999...1), (Self.rotation(0, 0, 0, 8, -5), 0.95...1),
      (Self.rotation(140, 320, 240, 0, 0), 0.5...1),
      (Self.rotation(0, 0, 0, 6000, -4000), 0...0.001),
      (Self.rotation(0, 0, 0, 320, 0), 0.45...0.55), ([Double](repeating: 0, count: 9), 0...0),
    ]
    for (matrix, range) in overlaps {
      #expect(range.contains(Homography.footprintOverlap(matrix, width: 640, height: 480)))
    }
    for degrees in [0.0, 30, 140, -35, 179] {
      #expect(
        abs(Homography.rotationDegrees(Self.rotation(degrees, 100, 100, 12, -7)) - degrees) <= 1e-9)
    }
  }
}
