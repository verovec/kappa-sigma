import StackKit
import Testing

/// Translated from `internal/grade/grade_test.go`.
@Suite("Grader — which registered subs are kept")
struct GraderTests {
  static func frame(
    _ index: Int, fwhm: Double, roundness: Double = 0, stars: Int = 0, background: Double = 0,
    trail: Bool = false, trailScore: Double = 0
  ) -> FrameGrade {
    var grade = FrameGrade(index: index, path: "")
    grade.fwhm = fwhm
    grade.roundness = roundness
    grade.starCount = stars
    grade.background = background
    grade.trailDetected = trail
    grade.trailScore = trailScore
    return grade
  }

  static func rejected(_ grades: [FrameGrade]) -> [Int: String] {
    Dictionary(uniqueKeysWithValues: grades.filter(\.rejected).map { ($0.index, $0.rejectReason) })
  }

  static func graded(_ grades: [FrameGrade], spans: [Range<Int>] = []) -> [FrameGrade] {
    var grades = grades
    Grader.grade(&grades, spans: spans)
    return grades
  }

  @Test("an elongated frame is rejected below the roundness floor")
  func testGrader_elongated() {
    let grades = Self.graded([
      Self.frame(1, fwhm: 3, roundness: 0.97, stars: 30),
      Self.frame(2, fwhm: 3, roundness: 0.96, stars: 30),
      Self.frame(3, fwhm: 3, roundness: 0.97, stars: 30),
      Self.frame(4, fwhm: 3, roundness: 0.50, stars: 30),
    ])
    #expect(Array(Self.rejected(grades).keys) == [4])
  }

  @Test("near-identical frames are not rejected because MAD is tiny")
  func testGrader_tightSet() {
    let grades = Self.graded([
      Self.frame(1, fwhm: 3.12, roundness: 0.97, stars: 30),
      Self.frame(2, fwhm: 3.12, roundness: 0.97, stars: 31),
      Self.frame(3, fwhm: 3.11, roundness: 0.97, stars: 30),
      Self.frame(4, fwhm: 3.13, roundness: 0.97, stars: 29),
    ])
    #expect(Self.rejected(grades).isEmpty)
  }

  @Test("a soft frame, clouds and a trail are rejected")
  func testGrader_softCloudsTrail() {
    let soft = Self.graded(
      (1...4).map { Self.frame($0, fwhm: 2, roundness: 0.97, stars: 30) } + [
        Self.frame(5, fwhm: 4, roundness: 0.97, stars: 30)
      ])
    #expect(Self.rejected(soft)[5] == "soft frame (FWHM 4.00 vs median 2.00)")
    let clouds = Self.graded([
      Self.frame(1, fwhm: 3, roundness: 0.97, stars: 40),
      Self.frame(2, fwhm: 3, roundness: 0.97, stars: 38),
      Self.frame(3, fwhm: 3, roundness: 0.97, stars: 41),
      Self.frame(4, fwhm: 3, roundness: 0.97, stars: 5),
    ])
    #expect(Self.rejected(clouds)[4] == "few stars (5 vs median 40) — likely clouds")
    let trail = Self.graded([
      Self.frame(1, fwhm: 3, roundness: 0.97, stars: 30),
      Self.frame(2, fwhm: 3, roundness: 0.97, stars: 30),
      Self.frame(3, fwhm: 3, roundness: 0.97, stars: 30, trail: true, trailScore: 0.9),
    ])
    #expect(Self.rejected(trail)[3] == "trail detected (score 0.90)")
  }

  @Test("the two sharpest flagged frames are restored for Siril's stack minimum, reason kept")
  func testGrader_stackMinimum() {
    let grades = Self.graded([
      Self.frame(1, fwhm: 3, roundness: 0.4, stars: 30),
      Self.frame(2, fwhm: 4, roundness: 0.3, stars: 30),
      Self.frame(3, fwhm: 5, roundness: 0.3, stars: 30),
    ])
    #expect(Array(Self.rejected(grades).keys) == [3])
    for kept in grades.prefix(2) {
      #expect(!kept.rejected)
      #expect(kept.rejectReason.hasPrefix(Grader.keptStackMinimumPrefix))
    }
  }

  static func flagged(_ index: Int, fwhm: Double, reason: String) -> FrameGrade {
    var grade = frame(index, fwhm: fwhm)
    grade.rejected = true
    grade.rejectReason = reason
    return grade
  }

  @Test(
    "keepAtLeast restores the best rejected up to n, capped by what registered",
    arguments: [
      (
        [
          flagged(1, fwhm: 2, reason: "soft"), flagged(2, fwhm: 3, reason: "soft"),
          flagged(3, fwhm: 4, reason: "soft"),
        ], [0, 1]
      ),
      ([flagged(1, fwhm: 2, reason: "trail"), flagged(2, fwhm: 0, reason: "not registered")], [0]),
      ([frame(1, fwhm: 2), frame(2, fwhm: 3), flagged(3, fwhm: 4, reason: "soft")], [0, 1]),
    ])
  func testGrader_keepAtLeast(grades: [FrameGrade], kept: [Int]) {
    var grades = grades
    Grader.keepAtLeast(&grades, 2)
    #expect(grades.indices.filter { !grades[$0].rejected } == kept)
  }

  @Test("the 1-based indices to unselect are the rejected ones")
  func testGrader_rejectedIndices() {
    let grades = [
      Self.frame(1, fwhm: 2), Self.flagged(2, fwhm: 2, reason: "x"), Self.frame(3, fwhm: 2),
    ]
    #expect(Grader.rejectedIndices(grades) == [2])
  }

  static func sharp(_ start: Int, _ count: Int) -> [FrameGrade] {
    (0..<count).map { frame(start + $0, fwhm: 2.5, roundness: 0.92, stars: 120, background: 0.01) }
  }

  static func soft(_ start: Int, _ count: Int) -> [FrameGrade] {
    (0..<count).map { frame(start + $0, fwhm: 4.8, roundness: 0.72, stars: 25, background: 0.03) }
  }

  @Test("per-night spans judge each night against itself (task #354)")
  func testGrader_softNightSurvivesPerSpan() {
    #expect(!Self.rejected(Self.graded(Self.sharp(1, 8) + Self.soft(9, 8))).isEmpty)
    #expect(
      Self.rejected(Self.graded(Self.sharp(1, 8) + Self.soft(9, 8), spans: [0..<8, 8..<16])).isEmpty
    )
  }

  @Test("absolute rules stay global inside any span")
  func testGrader_absoluteFloors() {
    let night =
      Self.soft(1, 6) + [
        Self.frame(7, fwhm: 4.8, roundness: 0.40, stars: 25, background: 0.03),
        Self.frame(8, fwhm: 4.8, roundness: 0.72, stars: 25, trail: true, trailScore: 3),
      ]
    let grades = Self.graded(night + Self.sharp(9, 6), spans: [0..<8, 8..<14])
    #expect(Set(Self.rejected(grades).keys) == [7, 8])
  }

  @Test("a span too small for statistics only gets the absolute rules")
  func testGrader_tinySpan() {
    let tiny = [
      Self.frame(1, fwhm: 9, roundness: 0.70, stars: 5, background: 0.09),
      Self.frame(2, fwhm: 2, roundness: 0.95, stars: 90, background: 0.01),
    ]
    #expect(Self.rejected(Self.graded(tiny + Self.sharp(3, 8), spans: [0..<2, 2..<10])).isEmpty)
  }

  @Test("the stack minimum is global: other spans' survivors count")
  func testGrader_stackMinimumGlobal() {
    let bad = [
      Self.frame(1, fwhm: 3, roundness: 0.9, stars: 30, trail: true, trailScore: 2),
      Self.frame(2, fwhm: 3, roundness: 0.9, stars: 30, trail: true, trailScore: 2),
    ]
    #expect(
      Set(Self.rejected(Self.graded(bad + Self.sharp(3, 4), spans: [0..<2, 2..<6])).keys) == [1, 2])
  }

  @Test("one span over everything is exactly the ungrouped grading")
  func testGrader_singleSpan() {
    let mixed = Self.sharp(1, 5) + Self.soft(6, 3) + [Self.frame(9, fwhm: 0)]
    #expect(Self.graded(mixed) == Self.graded(mixed, spans: [0..<mixed.count]))
  }
}
