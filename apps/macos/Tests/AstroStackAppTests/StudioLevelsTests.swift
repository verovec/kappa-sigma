import AstroStackApp
import Foundation
import Metal
import ProcessKit
import RenderKit
import TestSupport
import Testing

/// The histogram transformation in the Studio (card 0089): the viewer's display stretch offered
/// as one suggestion (the STF → HT handoff), the handles over the head's histogram, the
/// unlinked rows promoted, the clipping measured for display only.
@MainActor
@Suite(
  "Studio levels — display stretch handoff, handles, promoted rows, clipping",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioLevelsTests {
  static let reason = LevelsProcess.suggestionReasons[1]

  @Test(
    "the display stretch is one suggestion of its values, set only when taken", .scratchDirectory)
  func testFromDisplayStretchSuggestion() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let viewer = workspace.viewer.model
    let shown = STFParameters(shadows: 0.01, midtone: 0.2, highlights: 0.95)
    viewer.stretch = .manual
    viewer.manualSTF = Array(repeating: shown, count: 3)

    workspace.choose(LevelsProcess.id)
    let panel = try #require(workspace.panel)
    let offered = panel.suggestions.filter { $0.reason == Self.reason }
    #expect(offered.map(\.paramID) == ["linked", "rgbShadows", "rgbMidtones", "rgbHighlights"])
    #expect(offered.map(\.value) == [.flag(true), .number(0.01), .number(0.2), .number(0.95)])
    #expect(panel.params == ParamSet(schema: LevelsProcess.schema), "nothing set until taken")
    #expect(panel.groupedReasons.contains(Self.reason))
    panel.take(reason: Self.reason)
    #expect(LevelsProcess.stf("rgb", of: panel.params) == shown)

    // A per-channel display stretch: each channel's own triple, unlinked, RGB/K at identity.
    let red = STFParameters(shadows: 0.02, midtone: 0.3, highlights: 1)
    viewer.manualSTF = [red, shown, shown]
    workspace.choose(LevelsProcess.id)
    let unlinked = try #require(workspace.panel).suggestions.filter { $0.reason == Self.reason }
    #expect(
      unlinked.first == Suggestion(paramID: "linked", value: .flag(false), reason: Self.reason))
    #expect(
      unlinked.contains(Suggestion(paramID: "rMidtones", value: .number(0.3), reason: Self.reason)))
    #expect(
      unlinked.contains(
        Suggestion(paramID: "rgbMidtones", value: .number(0.5), reason: Self.reason)))

    // No display stretch, no suggestion of it; another process never gets it.
    viewer.stretch = .off
    workspace.choose(LevelsProcess.id)
    #expect(try #require(workspace.panel).suggestions.allSatisfy { $0.reason != Self.reason })
    viewer.stretch = .manual
    workspace.choose(CurvesProcess.id)
    #expect(try #require(workspace.panel).suggestions.allSatisfy { $0.reason != Self.reason })
  }

  @Test(
    "handles over the head's histogram: a drag sets its value; unlinked rows promoted",
    .scratchDirectory)
  func testPanelHandles() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.choose(LevelsProcess.id)
    let panel = try #require(workspace.panel)
    let sample = try #require(panel.sample)
    #expect(sample.bins.count == 3 && sample.bins[0].count == HeadSample.binCount)
    #expect(panel.handles == [STFParameters.identity.handlePositions(in: .linear)])
    #expect(panel.clipping.allSatisfy { $0.low == 0 && $0.high == 0 }, "nothing clipped untouched")

    panel.drag(.shadows, channel: 0, to: 0.05)
    #expect(panel.params.number("rgbShadows") == 0.05)
    // Measured on the head itself: the share of each channel at or below the black point.
    let expected = workspace.studio.head.planes.map { plane in
      Double(plane.filter { $0 <= 0.05 }.count) / Double(plane.count)
    }
    #expect(panel.clipping.map(\.low) == expected && expected[0] > 0)
    await workspace.previewNow()
    #expect(workspace.isPreviewing)

    #expect(!panel.visibleSpecs.map(\.id).contains("rShadows"))
    panel.set("linked", .flag(false))
    #expect(panel.visibleSpecs.map(\.id).contains("rShadows"), "unlinked: promoted")
    #expect(panel.handles.count == 3)
    #expect(panel.step(for: "rgbShadows") == ParameterStep(0.001))

    workspace.choose(StretchProcess.id)
    let stretch = try #require(workspace.panel)
    #expect(stretch.handles.count == 1 && stretch.clipping.isEmpty)
    let target = stretch.params.number("targetBackground")
    stretch.drag(.midtone, channel: 0, to: 0.2)
    #expect(stretch.params.number("targetBackground") != target)
    workspace.choose(CurvesProcess.id)
    #expect(try #require(workspace.panel).handles.isEmpty)
  }
}

extension StudioLevelsTests {
  @Test(
    "the levels panel shows the histogram, the clipping and a take-together button per reason",
    .scratchDirectory)
  func testPanelView() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.choose(LevelsProcess.id)
    let panel = try #require(workspace.panel)
    for language in ["fr", "en"] {
      let entries = AccessibilityAuditTests.entries(ProcessPanel(model: panel), language: language)
      let ids = entries.map(\.id)
      #expect(ids.contains("fr.astrostack.histogram.studio.levels.canvas"), "\(ids)")
      // Siril's autostretch and the display stretch: one button each.
      #expect(ids.contains("fr.astrostack.parameter.levels.together.0.suggestion"))
      #expect(ids.contains("fr.astrostack.parameter.levels.together.1.suggestion"))
      #expect(ids.contains("fr.astrostack.parameter.levels.rgbShadows.slider"))
      #expect(AccessibilityAudit.problems(entries) == [])
    }
    #expect(AstroFormat(locale: Locale(identifier: "fr")).share(0.125) == "12,50\u{a0}%")
  }
}

extension StudioLevelsTests {
  @Test(
    "the offered display stretch follows the viewer: a new manual stretch is offered",
    .scratchDirectory)
  func testDisplaySuggestionFollowsViewer() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.viewer.model.stretch = .manual
    workspace.choose(LevelsProcess.id)
    let panel = try #require(workspace.panel)
    let moved = STFParameters(shadows: 0.03, midtone: 0.15, highlights: 0.9)
    workspace.viewer.model.manualSTF = Array(repeating: moved, count: 3)
    let expected = Suggestion(paramID: "rgbMidtones", value: .number(0.15), reason: Self.reason)
    for _ in 0..<100 where !panel.suggestions.contains(expected) { await Task.yield() }
    #expect(panel.suggestions.contains(expected), "\(panel.suggestions)")
  }
}
