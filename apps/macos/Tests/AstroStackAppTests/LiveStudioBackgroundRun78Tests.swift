import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import StackKit
import TestSupport
import Testing

/// Card 0092's manual walk on run #78's recorded crop (`rgb_base`, Hα, [OIII]): background
/// extraction with the installed GraXpert on the RGB base, then compare with the step before and
/// the model view, rendered in French and English (PNG attachments, the PR's screenshots).
/// Skips without the finish fixtures or GraXpert.
@MainActor
@Suite(
  "Live background extraction on run #78's crop — GraXpert, compare, model view", .finishOracle,
  .tags(.live), .serialized, .timeLimit(.minutes(10)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"),
  .enabled(
    if: FileManager.default.fileExists(atPath: HostTools.graxpertDefaultPath),
    "GraXpert not installed"))
struct LiveStudioBackgroundRun78Tests {
  @Test("GraXpert on rgb_base: one step, corrected + model = input, model view", .scratchDirectory)
  func testGraXpertWalk() async throws {
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
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color, .emission])
    let input = studio.head

    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.refreshTools()
    #expect(workspace.missingTool == nil)
    try LiveStudioRun78Tests.render(workspace, "bge-1-panel")
    await workspace.runBatch()
    #expect(workspace.failure == nil)
    #expect(studio.steps.map(\.processID) == ["channel-combination", "background-extraction"])

    // Subtract: corrected + model gives the input back (GraXpert's FITS round trip, float32).
    let model = try #require(
      try studio.session.history.writtenLayers()[LayerRole.backgroundModel.rawValue])
    var worst: Float = 0
    for (plane, (corrected, removed)) in zip(input.planes, zip(studio.head.planes, model.planes)) {
      for index in plane.indices {
        worst = max(worst, abs(corrected[index] + removed[index] - plane[index]))
      }
    }
    #expect(worst <= 1e-5, "max |corrected + model − input| = \(worst)")
    #expect(studio.head.planes != input.planes, "GraXpert changed the image")

    try workspace.compare(toStep: 0)
    try LiveStudioRun78Tests.render(workspace, "bge-2-compare-before-after")
    try workspace.compare(toStep: nil)
    try workspace.toggleModel()
    #expect(workspace.showsModel)
    try LiveStudioRun78Tests.render(workspace, "bge-3-model")
    // The viewer is Metal (blank in an offscreen capture): the pixels themselves, autostretched.
    for (name, image) in [("before", input), ("after", studio.head), ("model", model)] {
      try Self.attach(image, named: "studio-run78-bge-\(name).png")
    }
  }

  /// `image` through Siril's autostretch per plane (c0 = median − 2.8 σ, median → 0.25), as a
  /// 16-bit PNG attachment.
  static func attach(_ image: AstroImage, named name: String) throws {
    let planes = image.planes.map { plane -> [Float] in
      let sorted = plane.sorted()
      let median = Double(sorted[sorted.count / 2])
      let deviations = plane.map { abs(Double($0) - median) }.sorted()
      let madn = 1.4826 * deviations[deviations.count / 2]
      let c0 = max(0, median - 2.8 * madn)
      let midtone = MTF.apply(0.25, median - c0)
      return plane.map { Float(MTF.apply(midtone, max(0, (Double($0) - c0) / (1 - c0)))) }
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try ImageExport.write(
      AstroImage(
        width: image.width, height: image.height, planes: planes, metadata: image.metadata),
      to: url, format: .png16)
    Attachment.record(try Data(contentsOf: url), named: name)
  }
}
