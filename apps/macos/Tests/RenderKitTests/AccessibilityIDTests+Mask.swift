import RenderKit
import Testing

/// Card 0111: the inactive mask row's « Clear mask » has its own identifier among the mask's.
@Suite("AccessibilityID — the Studio's mask controls")
struct AccessibilityIDMaskTests {
  @Test("each mask control has its own identifier under the Studio stage")
  func testMaskIdentifiers() {
    let ids: [AccessibilityID] = [.studioMaskSource, .studioMaskInvert, .studioMaskClear]
    let raw = ids.map(\.rawValue)
    #expect(Set(raw).count == 3)
    #expect(raw.allSatisfy { $0.hasPrefix("fr.astrostack.stage.studio.mask.") })
    #expect(AccessibilityID.studioMaskClear.rawValue.hasSuffix("mask.clear"))
  }
}
