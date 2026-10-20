import Foundation
import StackKit
import Testing

/// `EdgeTrim` is the legacy `measureEdgeTrim` (`internal/pipeline/edgecrop.go`): the ragged edge a
/// registered stack carries is measured on the finished master and kept away from the sky model.
/// Cases translated from `edgecrop_test.go`; the frame is 2400×900, so the 200 px skirt is 3% of
/// a real 6064 px master.
@Suite("EdgeTrim — the stacking edge, measured")
struct EdgeTrimTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let build: @Sendable () -> EdgeFrame
    let wantCut: Bool
    var capped = false
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    // The failure this exists for.
    Case(name: "drift wedge and its skirt are cut", build: { drifted() }, wantCut: true),
    Case(name: "a clean frame is left alone", build: { EdgeFrame() }, wantCut: false),
    // A real light-pollution dome (10% of the sky) survives: the border test measures departure
    // from a fitted TREND, not from a level.
    Case(name: "a real light-pollution gradient survives", build: { gradient() }, wantCut: false),
    // An object in the middle cannot capture the clipped, whole-profile trend fit.
    Case(
      name: "a bright object in the middle is not a border", build: { centred() }, wantCut: false),
    // The reason the noise clause exists: a nebula off the frame is off-level but full depth.
    Case(
      name: "an object running off the edge is kept", build: { edgeObject() }, wantCut: false),
    Case(
      name: "a ragged edge under an object is still cut", build: { edgeObject(drift: true) },
      wantCut: true),
    // A frame that is border all the way in keeps its field and says so.
    Case(
      name: "an absurd measurement is capped, not obeyed", build: { absurd() }, wantCut: true,
      capped: true),
  ]

  @Test(
    "the trim cuts the stack's edge and nothing else, within the per-side cap", arguments: cases)
  func testMeasure(_ example: Case) {
    let frame = example.build()
    let (rect, capped) = frame.measure()
    let (capX, capY) = (Int(EdgeTrim.maxTrimFraction * 2400), Int(EdgeTrim.maxTrimFraction * 900))
    #expect(capped == example.capped)
    #expect(rect.x0 >= 0 && rect.x1 <= 2400)
    #expect(rect.x0 <= capX && 2400 - rect.x1 <= capX && rect.y0 <= capY)
    if example.wantCut {
      #expect(rect.area < 2400 * 900)
    } else {
      #expect(rect == EdgeRect(x0: 0, y0: 0, x1: 2400, y1: 900))
    }
  }

  @Test("the trim lands past the skirt, not merely past the dead pixels")
  func testMeasure_landsPastTheSkirt() {
    let (rect, capped) = Self.drifted().measure()
    #expect(!capped)
    #expect(rect.x0 > 100, "trimming only the dead wedge leaves the +25 sigma band in")
    #expect(rect.x0 < 300, "and it must not keep going into clean sky")
    #expect(rect.x1 == 2400 && rect.y0 == 0 && rect.y1 == 900)
  }

  @Test("re-measuring what was kept finds nothing left to cut")
  func testMeasure_idempotent() {
    let frame = Self.drifted()
    let kept = frame.cropped(to: frame.measure().rect)
    let (again, capped) = kept.measure()
    #expect(!capped)
    #expect(again == EdgeRect(x0: 0, y0: 0, x1: kept.width, y1: kept.height))
  }

  @Test("planes are averaged per pixel; a frame too small to profile is left whole")
  func testMeasure_planesAndSmallFrames() {
    let frame = Self.drifted()
    let half = frame.pixels.map { $0 / 2 }
    let rgb = EdgeTrim.measure([half, half, frame.pixels.map { $0 * 2 }], width: 2400, height: 900)
    #expect(rgb.rect.x0 > 100)
    let small = EdgeTrim.measure([[Float](repeating: 0, count: 100 * 100)], width: 100, height: 100)
    #expect(small.rect == EdgeRect(x0: 0, y0: 0, x1: 100, y1: 100) && !small.capped)
  }

  @Test("rectangles intersect to their common field")
  func testRect_intersect() {
    let common = EdgeRect(x0: 10, y0: 0, x1: 100, y1: 50).intersect(
      EdgeRect(x0: 0, y0: 5, x1: 90, y1: 60))
    #expect(common == EdgeRect(x0: 10, y0: 5, x1: 90, y1: 50))
    #expect(common.width == 80 && common.height == 45 && common.area == 3600)
  }

  static func drifted() -> EdgeFrame {
    var frame = EdgeFrame()
    frame.addDriftEdge(wedge: 40, skirt: 200)
    return frame
  }

  static func gradient() -> EdgeFrame {
    var frame = EdgeFrame()
    frame.add { x, y in
      let (across, down) = (x / 2400, y / 900)
      return 0.10 * EdgeFrame.sky * (across * across * 0.6 + across * 0.4) + 0.04 * EdgeFrame.sky
        * down
    }
    return frame
  }

  static func centred() -> EdgeFrame {
    var frame = EdgeFrame()
    frame.add { x, y in
      let (dx, dy) = ((x - 1200) / 110, (y - 450) / 70)
      return 0.30 * exp(-0.5 * (dx * dx + dy * dy))
    }
    return frame
  }

  static func edgeObject(drift: Bool = false) -> EdgeFrame {
    var frame = EdgeFrame()
    frame.addEdgeObject()
    if drift { frame.addDriftEdge(wedge: 40, skirt: 200) }
    return frame
  }

  static func absurd() -> EdgeFrame {
    var frame = EdgeFrame()
    frame.addDriftEdge(wedge: 900, skirt: 2400)
    return frame
  }
}
