import AstroStackApp
import Foundation
import Metal
import Observation
import ProcessKit
import TestSupport
import Testing

/// Card 0187: the levels' « display stretch » suggestion follows the viewer's stretch, not its
/// zoom — a wheel tick over the image never measures the head again.
@MainActor
@Suite(
  "StudioWorkspaceModel — the suggestions follow the stretch, not the zoom",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioWorkspaceModelOffersTests {
  /// Counts the times `panel.suggestions` is written, re-arming after each one.
  @MainActor
  final class Rebuilds {
    private(set) var times = 0
    private let panel: ProcessPanelModel

    init(_ panel: ProcessPanelModel) {
      self.panel = panel
      arm()
    }

    private func arm() {
      withObservationTracking {
        _ = panel.suggestions
      } onChange: { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          self.times += 1
          self.arm()
        }
      }
    }
  }

  /// A yield lets the observation's change land (it is delivered on the main actor as a task).
  static func settle() async {
    for _ in 0..<3 { await Task.yield() }
  }

  @Test("testOffers_ZoomDoesNotRemeasure", .scratchDirectory)
  func testOffers_ZoomDoesNotRemeasure() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.viewer.model.viewSize = SIMD2(400, 300)
    workspace.choose(LevelsProcess.id)
    let panel = try #require(workspace.panel)
    await Self.settle()
    let rebuilds = Rebuilds(panel)

    for _ in 0..<5 { workspace.viewer.model.zoom(by: 1.25, atView: SIMD2(100, 100)) }
    await Self.settle()
    #expect(rebuilds.times == 0, "a zoom changes no stretch: nothing to offer again")

    workspace.viewer.model.stretch = .off
    await Self.settle()
    #expect(rebuilds.times == 1, "the stretch changed: the suggestion is rebuilt once")
  }
}
