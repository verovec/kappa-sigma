import AstroStackApp
import Foundation
import ProcessKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// Card 0111: a mask set for an earlier process stays on; under a panel that takes none (a host
/// tool, geometry) the side column says so, with Clear — never reset behind the user's back (R2).
@MainActor
@Suite("Studio inactive mask row — the mask shown where a process does not take it")
struct StudioInactiveMaskRowTests {
  static let clear = AccessibilityID.studioMaskClear.rawValue
  static let source = AccessibilityID.studioMaskSource.rawValue
  static let mask = Mask(source: .stars(threshold: 0.02, radiusPx: 8))

  static func ids(_ workspace: StudioWorkspaceModel) -> Set<String> {
    Set(AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
  }

  @Test(
    "background extraction under a mask: the row and Clear; none without a mask",
    .scratchDirectory)
  func testInactiveRow_ShownForBackgroundExtraction_WhenMaskSet() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try BackgroundProcessTests.workspace(opened)
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(!Self.ids(workspace).contains(Self.clear))

    workspace.mask = Self.mask
    let ids = Self.ids(workspace)
    #expect(ids.contains(Self.clear))
    #expect(!ids.contains(Self.source), "the mask is not edited under a host tool")
  }

  @Test("geometry under a mask: the row says it is ignored, with Clear", .scratchDirectory)
  func testInactiveRow_ShownForGeometry_SaysIgnored() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try BackgroundProcessTests.workspace(opened)
    workspace.mask = Self.mask
    workspace.choose(GeometryProcess.id)
    #expect(Self.ids(workspace).contains(Self.clear))
    let (ignored, blocked) = (
      StudioInactiveMaskRow.note(geometry: true, source: "Stars"),
      StudioInactiveMaskRow.note(geometry: false, source: "Stars")
    )
    #expect(String(localized: ignored).contains("ignored"))
    #expect(String(localized: blocked).contains("blocked"))
  }

  @Test("Clear unblocks the host tool, and the fake tool runs", .scratchDirectory)
  func testClearMask_UnblocksHostTool() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let calls = BackgroundProcessTests.Calls()
    let workspace = try BackgroundProcessTests.workspace(
      opened, tool: BackgroundProcessTests.tool(calls: calls))
    workspace.mask = Self.mask
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(workspace.toolRefusal != nil)
    #expect(await workspace.runTool() == false && calls.engines.isEmpty)

    workspace.clearMask()
    #expect(workspace.mask == nil && workspace.toolRefusal == nil)
    #expect(await workspace.runTool())
    #expect(calls.engines.count == 1)
  }

  @Test("the mask survives choosing another process (never reset in silence)", .scratchDirectory)
  func testMask_KeptAcrossChoose() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try BackgroundProcessTests.workspace(opened)
    workspace.choose(StretchProcess.id)
    workspace.mask = Self.mask
    workspace.choose(BackgroundExtractionProcess.id)
    workspace.choose(StretchProcess.id)
    #expect(workspace.mask == Self.mask)
    #expect(Self.ids(workspace).contains(Self.source), "a masked process edits it again")
  }
}
