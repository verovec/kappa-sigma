import AstroStackApp
import Foundation
import ProcessKit
import StackKit
import Testing

extension StudioWorkspaceModelTests {
  @Test(
    "the denoise panel offers the head's measured noise as its noise level (card 0115)",
    .scratchDirectory)
  func testDenoise_OffersMeasuredNoise() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(DenoiseProcess.id)
    let panel = try #require(workspace.panel)
    await workspace.settleNoise()

    let head = workspace.studio.head
    let measured = head.planes.map {
      StarletDenoiser.measure($0, width: head.width, height: head.height)
    }
    let expected = DenoiseProcess.suggestions(measured: measured)
    #expect(!expected.isEmpty)
    #expect(panel.suggestions == expected)
    #expect(panel.params.number("noise") == 0, "offered, never applied")
  }
}
