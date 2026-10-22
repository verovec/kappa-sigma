import RenderKit
import Testing

/// Card 0088: the pipeline column's identifiers, one per control, under the Studio stage.
@Suite("AccessibilityID — the Studio's pipeline column")
struct AccessibilityIDPipelineTests {
  @Test("each pipeline control has its own identifier")
  func testPipelineIdentifiers() {
    let ids: [AccessibilityID] = [
      .studioPipelineRun, .studioPipelineContinue, .studioPipelineReplay, .studioPipelineFiles,
      .studioPipelineSaveAs, .studioPipelineName, .studioPipelineSave, .studioPipelineCancel,
      .studioPipelineLoad, .studioPipelineCompare, .studioPipelineCompareClose,
      .studioPipelineReplayCancel, .studioPipelineSaved(0, compare: false),
      .studioPipelineSaved(0, compare: true), .studioPipelineStep(2, lock: false),
      .studioPipelineStep(2, lock: true), .studioPipelineReplayTarget(7),
    ]
    let raw = ids.map(\.rawValue)
    #expect(Set(raw).count == ids.count)
    #expect(raw.allSatisfy { $0.hasPrefix("fr.astrostack.stage.studio.pipeline.") })
    #expect(AccessibilityID.studioPipelineStep(2, lock: true).rawValue.hasSuffix("step.2.lock"))
  }
}
