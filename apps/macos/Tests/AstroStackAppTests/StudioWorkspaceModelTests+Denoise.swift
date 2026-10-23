import AstroStackApp
import Foundation
import ProcessKit
import StackKit
import Testing

extension StudioWorkspaceModelTests {
  @Test(
    "the denoise panel offers the scale-1 strength from the head's measured noise (card 0115)",
    .scratchDirectory)
  func testDenoise_OffersMeasuredNoise() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(DenoiseProcess.id)
    let panel = try #require(workspace.panel)
    await workspace.settleNoise()

    let head = workspace.studio.head
    let noise = StarletDenoiser.measure(head.planes[0], width: head.width, height: head.height)
    let stats = workspace.studio.session.stepStats
    let expected = DenoiseProcess.suggestions(noise: noise, stats: stats)
    #expect(!expected.isEmpty)
    #expect(panel.suggestions == expected)
    #expect(panel.params.number("scale1") == DenoiseProcess.presetStrengths[0], "never applied")
  }
}
