import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// An Apply whose values change nothing is recorded — the pipeline keeps its steps, R5 — and
/// said, so an Undo that shows nothing is understood.
extension StudioWorkspaceModelTests {
  /// The workspace after an Apply of `processID` at its defaults.
  static func applied(_ processID: String, _ opened: StudioModelTests.Opened) async throws
    -> StudioWorkspaceModel
  {
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(processID)
    await workspace.previewNow()
    try workspace.apply()
    return workspace
  }

  @Test("a step that changes nothing is recorded and said", .scratchDirectory)
  func testApply_ChangesNothing_IsSaid() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.applied(SaturationProcess.id, opened)
    #expect(workspace.studio.steps.count == 2 && workspace.appliedNothing)
  }

  @Test("a step that changes the image says nothing more", .scratchDirectory)
  func testApply_ChangesTheImage_NotSaid() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.applied(StretchProcess.id, opened)
    #expect(workspace.studio.steps.count == 2 && !workspace.appliedNothing)
  }

  @Test("the notice goes with the head it spoke of", .scratchDirectory)
  func testAppliedNothing_ClearedByUndo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.applied(SaturationProcess.id, opened)
    try workspace.undo()
    #expect(!workspace.appliedNothing)
  }

  @Test("the notice goes once a value moves, or another process is chosen", .scratchDirectory)
  func testAppliedNothing_ClearedByAValueOrAChoice() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.applied(SaturationProcess.id, opened)
    try #require(workspace.panel).set("amount", .number(0.5))
    #expect(!workspace.appliedNothing)
    let again = try await Self.applied(SaturationProcess.id, opened)
    again.choose(StretchProcess.id)
    #expect(!again.appliedNothing)
  }
}

@Suite("StudioSession.samePixels — bits, not values")
struct StudioSessionSamePixelsTests {
  @Test(
    "equal bits are the same, a NaN included; any other difference is not",
    arguments: [
      ([[Float(1), .nan]], [[Float(1), .nan]], true),
      ([[Float(1), 2]], [[Float(1), 3]], false),
      ([[Float(1)]], [[Float(1)], [Float(1)]], false),
      ([[Float]()], [[Float]()], true),
    ])
  func testSamePixels(one: [[Float]], two: [[Float]], same: Bool) {
    #expect(StudioSession.samePixels(one, two) == same)
  }
}
