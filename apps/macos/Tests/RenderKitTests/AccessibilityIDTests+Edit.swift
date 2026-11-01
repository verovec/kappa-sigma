import RenderKit
import Testing

/// Card 0159: the re-edit and Versions controls, one identifier each, under the Studio stage.
@Suite("AccessibilityID — re-edit and history versions")
struct AccessibilityIDEditTests {
  @Test("each re-edit and Versions control has its own identifier")
  func testEditIdentifiers() {
    let ids: [AccessibilityID] = [
      .studioStepCompare(2), .studioEditCancel, .studioEditApply, .studioVersions,
      .studioVersion(0, "compare"), .studioVersion(0, "restore"), .studioVersion(0, "drop"),
      .studioVersion(1, "drop"), .studioStep(2),
    ]
    let raw = ids.map(\.rawValue)
    #expect(Set(raw).count == ids.count)
    #expect(raw.allSatisfy { $0.hasPrefix("fr.astrostack.stage.studio.") })
    #expect(AccessibilityID.studioStepCompare(2).rawValue.hasSuffix("step.2.compare"))
    #expect(AccessibilityID.studioVersion(1, "drop").rawValue.hasSuffix("versions.1.drop"))
  }
}
