import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0176: every stage's pane, in every state, fits the detail column the window minimum
/// keeps for it. A pane wider than that column made the split view republish a minimum it could
/// never get, and AppKit looped until it raised (crashes of 29/10 and 06/11).
@MainActor
@Suite(
  "Stage panes — each fits the detail column at the window minimum",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StagePaneMinimumTests {
  /// The smallest size `view` lays out in: what it reports for a zero proposal.
  static func minimum(_ view: some View) -> CGSize {
    NSHostingController(rootView: view.environment(\.locale, Locale(identifier: "fr")))
      .sizeThatFits(in: .zero)
  }

  static func expectFits(_ view: some View, _ state: String) {
    let size = Self.minimum(view)
    let budget = SplitWindow.detailMinSize
    #expect(size.width <= budget.width, "\(state): \(size.width) pt wide > \(budget.width)")
    #expect(size.height <= budget.height, "\(state): \(size.height) pt high > \(budget.height)")
  }

  @Test("an empty project: every stage fits", .scratchDirectory, arguments: JourneyStage.allCases)
  func testEmptyStage_fits(_ stage: JourneyStage) throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    fixture.window.select(stage)
    Self.expectFits(StagePane.pane(for: stage, model: fixture.window), "\(stage)")
  }

  enum StudioState: String, CaseIterable, Sendable {
    case panelShown, panelHidden, processOpen, focused
  }

  @Test("the Studio on a loaded stack fits", .scratchDirectory, arguments: StudioState.allCases)
  func testStudio_fits(_ state: StudioState) async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    let output = fixture.project.url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try ProjectTests.writeBundle(in: output, runID: "A")
    _ = try fixture.project.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    let window = fixture.window
    window.refresh()
    window.select(.studio)
    await window.openStudio()
    await ProjectWindowWorkspaceTests.settle { window.workspace != nil || window.error != nil }
    let workspace = try #require(window.workspace)
    let viewer = workspace.viewer.model
    // The panel's visibility is the user's stored choice: put back before any other test reads it,
    // in the same main-actor turn.
    let shown = viewer.showsPanel
    defer { viewer.showsPanel = shown }
    switch state {
    case .panelShown: viewer.showsPanel = true
    case .panelHidden: viewer.showsPanel = false
    case .processOpen: workspace.choose("stretch")
    case .focused: workspace.toggleFocus()
    }
    Self.expectFits(StagePane.pane(for: .studio, model: window), state.rawValue)
  }

  @Test("Stacking with a finished run fits", .scratchDirectory)
  func testStackingRun_fits() async throws {
    let open = Recorded<AsyncThrowingStream<PreprocessEvent, any Error>.Continuation>()
    let fixture = try ProjectTests.fixture(run: RunPanelTests.run(.finished, open: open))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.startRun()
    await window.run?.settled()
    window.select(.stacking)
    Self.expectFits(StagePane.pane(for: .stacking, model: window), "stacking")
  }

  @Test("Review on a paused lane, table and blink, fits", .scratchDirectory)
  func testReviewPaused_fits() async throws {
    let ran = Recorded<PreprocessRequest>()
    let fixture = try ProjectTests.fixture(
      run: ReviewPaneTests.pausingRun(thumbnails: try ReviewPaneTests.thumbnails(), seen: ran))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.knobs.set(KnobSchema.frameReviewID, to: .flag(true))
    window.startRun()
    let run = try #require(window.run)
    await ReviewPaneTests.settlePause(run)
    #expect(run.paused?.isLive == true)
    window.select(.review)
    Self.expectFits(StagePane.pane(for: .review, model: window), "review")
    window.cancelRun()
    await run.settled()
  }

  @Test(
    "at the opening size, sidebar at its ideal, the Studio shows its View panel", .scratchDirectory)
  func testStudioOpening_showsViewPanel() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let viewer = workspace.viewer.model
    let shown = viewer.showsPanel
    defer { viewer.showsPanel = shown }
    viewer.showsPanel = true
    let detail =
      SplitWindow.openingPanes.width - SplitWindow.sidebarWidth.ideal - SplitWindow.dividers
    let ids = Set(
      AccessibilityAuditTests.entries(StudioWorkspaceView(model: workspace), width: detail)
        .map(\.id))
    #expect(ids.contains(AccessibilityID.viewer("histogramDomain").rawValue), "\(detail) pt")
  }

  @Test("the side column's content fits its minimum, a process panel open", .scratchDirectory)
  func testStudioSide_contentFitsColumn() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.choose("stretch")
    let side = Self.minimum(StudioSideView(model: workspace))
    #expect(side.width <= StudioWorkspaceView.sideWidth.min - 1, "\(side.width) pt")
  }
}
