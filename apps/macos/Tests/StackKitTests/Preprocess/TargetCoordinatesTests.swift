import StackKit
import Testing

/// `TargetCoordinates` is `skycat.ParseRA`/`ParseDec` + `targetQueryFor`: the lights' own
/// pointing as the plate-solve hint.
@Suite("TargetCoordinates — the plate-solve hint from the lights' headers")
struct TargetCoordinatesTests {
  @Test(
    "sexagesimal and decimal forms; a sign counts for the declination only, as in Go",
    arguments: [
      ("00 42 44.3", "+41 16 09", 10.684583333, 41.269166667),
      ("00:42:44.3", "-05:23:00", 10.684583333, -5.383333333),
      ("10.6846", "41.2692", 10.6846, 41.2692), ("-00 30 00", "-00 30 00", 7.5, -0.5),
    ])
  func testParse(ra: String, dec: String, wantRA: Double, wantDec: Double) throws {
    #expect(abs(try #require(TargetCoordinates.rightAscension(ra)) - wantRA) <= 1e-6)
    #expect(abs(try #require(TargetCoordinates.declination(dec)) - wantDec) <= 1e-6)
  }

  @Test("empty or unparseable is no hint")
  func testInvalid() {
    #expect(
      TargetCoordinates.rightAscension("") == nil && TargetCoordinates.declination("12 ab") == nil)
    #expect(TargetCoordinates.rightAscension("1 2 3 4") == nil)
  }

  @Test("the first light with both cards gives the hint, five decimals")
  func testFromInventory() {
    var frame = CaptureFrame(path: "/a.fits")
    frame.objectRA = "00 42 44.3"
    frame.objectDec = "+41 16 09"
    var inventory = Inventory(root: "/", frames: [])
    inventory.sets = [
      FrameSet(
        key: SetKey(type: .light, filter: "L"), frames: [CaptureFrame(path: "/b.fits"), frame],
        indices: [0, 1])
    ]
    #expect(TargetCoordinates.from(inventory) == "10.68458,41.26917")
    inventory.sets[0].frames.removeLast()
    #expect(TargetCoordinates.from(inventory) == nil)
  }
}
