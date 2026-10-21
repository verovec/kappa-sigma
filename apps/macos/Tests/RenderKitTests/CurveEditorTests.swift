import RenderKit
import Testing

/// `CurveEditorPoints`, the model behind `CurveEditor`: points stay sorted, in [0, 1], a minimum
/// gap apart, between 2 and `maxCount`.
@Suite("Curve editor — adding, dragging and removing control points")
struct CurveEditorTests {
  static let identity = CurveEditorPoints(maxCount: 4)

  @Test("a new editor is the identity: (0, 0) to (1, 1)")
  func testIdentity() {
    #expect(Self.identity.points == [SIMD2(0, 0), SIMD2(1, 1)])
    #expect(Self.identity.isIdentity)
  }

  @Test(
    "adding inserts in x order; too close to a point or past maxCount adds nothing",
    arguments: zip(
      [[0.5], [0.7, 0.3], [0.5, 0.505], [0.2, 0.4, 0.6]],
      [[0, 0.5, 1], [0, 0.3, 0.7, 1], [0, 0.5, 1], [0, 0.2, 0.4, 1]]))
  func testAdd(xs: [Double], expected: [Double]) {
    var editor = Self.identity
    for x in xs { editor.add(SIMD2(x, x)) }
    #expect(editor.points.map(\.x) == expected)
    #expect(!editor.isIdentity || xs.isEmpty || editor.points.allSatisfy { $0.x == $0.y })
  }

  @Test(
    "dragging clamps into [0, 1] and never past a neighbour",
    arguments: zip(
      [SIMD2(0.5, 1.4), SIMD2(1.2, 0.5), SIMD2(-0.1, 0.5)],
      [SIMD2(0.5, 1.0), SIMD2(0.99, 0.5), SIMD2(0.01, 0.5)]))
  func testMove(target: SIMD2<Double>, expected: SIMD2<Double>) {
    var editor = Self.identity
    editor.add(SIMD2(0.5, 0.5))
    editor.move(1, to: target)
    #expect(abs(editor.points[1].x - expected.x) < 1e-12)
    #expect(editor.points[1].y == expected.y)
    #expect(editor.points.map(\.x) == editor.points.map(\.x).sorted())
  }

  @Test("an end point moves vertically only; removing keeps two points")
  func testEndsAndRemove() {
    var editor = Self.identity
    editor.move(0, to: SIMD2(0.3, 0.2))
    #expect(editor.points[0] == SIMD2(0, 0.2))
    editor.remove(0)
    #expect(editor.points.count == 2, "never below two points")
    editor.add(SIMD2(0.5, 0.9))
    editor.remove(1)
    #expect(editor.points.map(\.x) == [0, 1])
    editor.reset()
    #expect(editor.isIdentity)
  }

  @Test("the nearest point within reach is found, nothing beyond it")
  func testNearest() {
    var editor = Self.identity
    editor.add(SIMD2(0.5, 0.6))
    #expect(editor.nearest(to: SIMD2(0.52, 0.58), within: 0.05) == 1)
    #expect(editor.nearest(to: SIMD2(0.3, 0.9), within: 0.05) == nil)
  }
}
