import AstroStackApp
import Foundation
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0116: the catalogue in the usual processing order, each row with its rank, and the
/// process usually next after the head marked — a suggestion only, nothing greyed (R2).
@MainActor
@Suite(
  "Studio catalogue — usual order, rank, « usually next »",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioCatalogueOrderTests {
  @Test("each stage group follows the usual order; ranks are the order's", .scratchDirectory)
  func testCatalogue_FollowsUsualOrder() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let linear = try #require(workspace.catalogue.first { $0.stage == .linear }).entries
    let ids = linear.map(\.id)
    let bge = try #require(ids.firstIndex(of: BackgroundExtractionProcess.id))
    let stretch = try #require(ids.firstIndex(of: StretchProcess.id))
    #expect(bge < stretch, "background extraction before the stretch (PO 23/10)")
    for group in workspace.catalogue {
      let ranks = group.entries.compactMap(\.rank)
      #expect(ranks == ranks.sorted(), "\(group.stage)")
      for entry in group.entries { #expect(entry.rank == ProcessOrder.rank(of: entry.id)) }
    }
  }

  @Test(
    "after the combination background extraction is usually next; after a stretch, levels",
    .scratchDirectory)
  func testUsuallyNext_AfterCombination_IsBackgroundExtraction() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    #expect(workspace.usuallyNext == BackgroundExtractionProcess.id)
    let greyed = workspace.catalogue.flatMap(\.entries).map(\.unavailable)

    workspace.choose(StretchProcess.id)
    try workspace.apply()
    #expect(workspace.usuallyNext == LevelsProcess.id)
    #expect(
      workspace.catalogue.flatMap(\.entries).map(\.unavailable).count == greyed.count,
      "the hint greys nothing")
    #expect(
      workspace.catalogue.flatMap(\.entries).first { $0.id == LevelsProcess.id }?.unavailable
        == nil)
  }
}
