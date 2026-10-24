import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import SwiftUI
import TestSupport
import Testing

/// Card 0119's manual walk on run #78's crop (M31, RGB base + Hα + [OIII]): stretch and screens on
/// the combined image, denoise the Hα branch only, compare Hα with the broadband branch, then
/// Replay on Combined — the Studio rendered in French and English at each stage (PNG attachments,
/// the PR's screenshots). Skips without the finish fixtures.
@MainActor
@Suite(
  "Live branch workspace on run #78's crop — denoise Hα, compare, Replay", .finishOracle,
  .tags(.live), .serialized, .timeLimit(.minutes(5)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LiveBranchWorkspaceRun78Tests {
  @Test("the walk: denoise Hα only, compare Hα with RGB, Replay on Combined", .scratchDirectory)
  func testWalk() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    try #require(FinishOracle.verify(manifest.layers, root: root) == [])
    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/78", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB", "Ha", "OIII"])
    let studio = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/78"),
      bundle: LiveStudioRun78Tests.bundle(root))
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try studio.apply(
      EmissionScreensProcess.id, params: ParamSet(schema: EmissionScreensProcess.schema))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color, .emission])
    #expect(workspace.selections == [.main, .branch("RGB"), .branch("Ha"), .branch("OIII")])

    workspace.select(.branch("Ha"))
    workspace.choose(DenoiseProcess.id)
    let panel = try #require(workspace.panel)
    panel.set("amount", .number(1))
    panel.set("noise", .number(0.02))
    await workspace.previewNow()
    try workspace.apply()
    #expect(studio.steps(of: .branch("Ha")).map(\.processID) == [DenoiseProcess.id])
    #expect(workspace.comparable.contains(.branch("RGB")))
    try workspace.compare(with: .branch("RGB"))
    #expect(workspace.comparingWith == .branch("RGB"))
    try LiveStudioRun78Tests.render(workspace, "branch-1-ha-denoised-vs-rgb")

    workspace.select(.main)
    #expect(workspace.staleNotice == StaleNotice(steps: [2], branches: ["Ha"]))
    try LiveStudioRun78Tests.render(workspace, "branch-2-stale")
    try await StudioUndo.replayMain(workspace, on: UndoManager())
    #expect(workspace.staleNotice == nil)
    #expect(workspace.failure == nil)
    try LiveStudioRun78Tests.render(workspace, "branch-3-replayed")
  }
}
