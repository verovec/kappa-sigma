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
    }
  }

  @Test(
    "after the combination background extraction is usually next; after a stretch, levels",
    .scratchDirectory)
  func testUsuallyNext_AfterCombination_IsBackgroundExtraction() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    // Without its tool the extraction is greyed: the hint passes it by.
    let bare = try StudioWorkspaceModelTests.workspace(opened, bundle: StudioModelTests.bundle())
    #expect(bare.usuallyNext != BackgroundExtractionProcess.id)
    let workspace = try BackgroundProcessTests.workspace(opened)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    #expect(workspace.usuallyNext == BackgroundExtractionProcess.id)
    let greyed = Dictionary(
      uniqueKeysWithValues: workspace.catalogue.flatMap(\.entries).map { ($0.id, $0.unavailable) })

    workspace.choose(StretchProcess.id)
    try workspace.apply()
    #expect(workspace.usuallyNext == LevelsProcess.id)
    for entry in workspace.catalogue.flatMap(\.entries) where entry.id != StretchProcess.id {
      // Only the stretch moved the data: every other row is greyed as before (R2).
      if greyed[entry.id] == nil { #expect(entry.unavailable == nil, "\(entry.id)") }
    }
    #expect(
      workspace.catalogue.flatMap(\.entries).first { $0.id == LevelsProcess.id }?.unavailable
        == nil)
  }
}
