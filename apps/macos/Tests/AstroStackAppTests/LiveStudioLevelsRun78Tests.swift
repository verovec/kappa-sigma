import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// Card 0089's manual walk on run #78's crop: stretch → levels, the shadows moved by 1e-4 steps
/// on the histogram, then unlinked with the blue midtones lifted; the Studio rendered in French
/// and English (PNG attachments, the PR's screenshots). Skips without the finish fixtures.
@MainActor
@Suite(
  "Live Studio levels on run #78's crop — fine shadows, unlinked blue midtones", .finishOracle,
  .tags(.live), .serialized, .timeLimit(.minutes(5)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LiveStudioLevelsRun78Tests {
  @Test("stretch, then levels: shadows in 1e-4 steps, blue midtones lifted", .scratchDirectory)
  func testLevelsWalk() async throws {
    let root = try #require(FinishOracle.root)
    try #require(FinishOracle.verify(try FinishOracle.manifest().layers, root: root) == [])
    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/78", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB", "Ha", "OIII"])
    let studio = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/78"),
      bundle: LiveStudioRun78Tests.bundle(root))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color, .emission])

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    try workspace.apply()
    workspace.viewer.model.stretch = .off

    workspace.choose(LevelsProcess.id)
    let levels = try #require(workspace.panel)
    let step = try #require(levels.step(for: "rgbShadows"))
    #expect(step.fine == 0.0001)
    for _ in 0..<3 {
      let moved = step.moved(levels.params.number("rgbShadows"), forward: true, fine: true)
      levels.set("rgbShadows", .number(moved))
    }
    #expect(levels.params.number("rgbShadows") == 0.0003)
    let clipped = levels.clipping
    #expect(clipped.count == 3 && clipped.allSatisfy { $0.low < 0.01 }, "\(clipped)")
    await workspace.previewNow()
    try LiveStudioRun78Tests.render(workspace, "levels-1-shadows")

    levels.set("linked", .flag(false))
    levels.set("bMidtones", .number(0.4))
    await workspace.previewNow()
    #expect(workspace.isPreviewing)
    try LiveStudioRun78Tests.render(workspace, "levels-2-blue-midtones")
    let head = studio.head.planes
    try workspace.apply()
    #expect(studio.steps.map(\.processID) == ["channel-combination", "stretch", "levels"])
    let applied = studio.head.planes
    let mean = { (plane: [Float]) in plane.map(Double.init).reduce(0, +) / Double(plane.count) }
    #expect(mean(applied[2]) > mean(head[2]), "the blue midtones lifted")
    #expect(applied[0] != head[0], "the shadows moved every channel")
  }
}
