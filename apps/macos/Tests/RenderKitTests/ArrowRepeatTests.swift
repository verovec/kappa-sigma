import RenderKit
import Testing

/// A held ↑/↓ speeds up (card 0179): the multiplier follows the auto-repeats counted since the
/// key went down, never a clock, so the same presses always move the value the same distance.
@Suite("ArrowRepeat — a held arrow moves 1, 2, 5 then 10 steps per repeat")
struct ArrowRepeatTests {
  @Test(
    "the n-th repeat moves 1, 2, 5 or 10 steps, by eights",
    arguments: zip([0, 7, 8, 15, 16, 23, 24, 100], [1, 1, 2, 2, 5, 5, 10, 10]))
  func testMultiplierTiersByRepeatCount(repeats: Int, multiplier: Int) {
    var arrows = ArrowRepeat()
    var last = arrows.steps(.down, accelerating: true)
    for _ in 0..<repeats { last = arrows.steps(.repeat, accelerating: true) }
    #expect(last == multiplier)
  }

  @Test("a key up, or a new press, starts again at one step")
  func testUpAndNewDownReset() {
    var arrows = ArrowRepeat()
    _ = arrows.steps(.down, accelerating: true)
    for _ in 0..<30 { _ = arrows.steps(.repeat, accelerating: true) }
    #expect(arrows.steps(.up, accelerating: true) == nil, "a release moves nothing")
    #expect(
      arrows.steps(.repeat, accelerating: true) == 1, "a repeat after a release counts from zero")
    for _ in 0..<30 { _ = arrows.steps(.repeat, accelerating: true) }
    #expect(arrows.steps(.down, accelerating: true) == 1, "a new press counts from zero")
  }

  @Test("a held key moves 8 + 16 + 40 steps over its first 24 events")
  func testDistanceOverAHold() {
    var arrows = ArrowRepeat()
    var total = arrows.steps(.down, accelerating: true) ?? 0
    for _ in 0..<23 { total += arrows.steps(.repeat, accelerating: true) ?? 0 }
    #expect(total == 8 + 16 + 40)
  }

  @Test("←/→ move one step per press or repeat, however long held, and nothing on release")
  func testHorizontalNeverAccelerates() {
    var arrows = ArrowRepeat()
    var total = arrows.steps(.down, accelerating: false) ?? 0
    for _ in 0..<23 { total += arrows.steps(.repeat, accelerating: false) ?? 0 }
    #expect(total == 24)
    #expect(arrows.steps(.up, accelerating: false) == nil)
  }
}
