import Foundation
import ProjectKit
import TestSupport
import Testing

/// A paused run's stack row (card 0097): status `paused` with its checkpoint, never listed with
/// the finished stacks, completed in place by Continue or deleted by Discard.
@Suite("ProjectStore: paused stacks (0007_stack_status)")
struct StackStatusStoreTests {
  static let checkpoint = #"{"lanes_done":["RGB"],"lanes_left":["RGB-dualband"],"run_id":"R1"}"#

  @Test(
    "a paused stack is listed apart, then completed in place with its images", .scratchDirectory)
  func testPausedStackCompleted() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let night = try store.addSource(kind: .night, path: "/captures/M31")
    let done = try store.addStack(bundlePath: "stacks/A", sourceIDs: [night.id], paramsJSON: "{}")
    let paused = try store.addStack(
      bundlePath: "stacks/B", sourceIDs: [night.id], paramsJSON: #"{"mode":"deepsky"}"#,
      object: "M 31", status: .paused, checkpointJSON: Self.checkpoint)
    #expect(done.status == .done && done.checkpointJSON == nil)
    #expect(paused.status == .paused && paused.checkpointJSON == Self.checkpoint)
    #expect(try store.stacks() == [done])
    #expect(try store.latestStack() == done)
    #expect(try store.pausedStacks() == [paused])
    #expect(try store.summary().stacks == 1, "a paused run is not a stack yet")

    let completed = try store.completeStack(
      id: paused.id, paramsJSON: #"{"mode":"nebula"}"#, imageRoles: ["R", "G", "B"])
    #expect(completed.status == .done && completed.checkpointJSON == nil)
    #expect(completed.paramsJSON == #"{"mode":"nebula"}"#)
    #expect(completed.sourceIDs == [night.id] && completed.object == "M 31")
    #expect(try store.pausedStacks().isEmpty)
    #expect(try store.stacks().map(\.id) == [done.id, paused.id])
    #expect(try store.images(stackID: paused.id).map(\.role) == ["R", "G", "B"])
  }

  @Test(
    "a paused stack is deleted with its sources links; a done one is refused", .scratchDirectory)
  func testPausedStackDiscarded() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let done = try store.addStack(bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}")
    let paused = try store.addStack(
      bundlePath: "stacks/B", sourceIDs: [], paramsJSON: "{}", status: .paused,
      checkpointJSON: Self.checkpoint)
    try store.deletePausedStack(id: paused.id)
    #expect(try store.pausedStacks().isEmpty)
    #expect(try store.stack(id: paused.id) == nil)
    #expect(throws: ProjectStoreError.self) { try store.deletePausedStack(id: done.id) }
    #expect(try store.stacks() == [done])
  }

  @Test(
    "down to 0006 drops the columns and the paused rows; up again reads every row done",
    .scratchDirectory)
  func testStackStatusUpDown() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    try store.addStack(bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}")
    try store.addStack(
      bundlePath: "stacks/B", sourceIDs: [], paramsJSON: "{}", status: .paused,
      checkpointJSON: Self.checkpoint)
    try store.migrate(to: 6)
    #expect(
      try store.columnNames(of: "stacks")
        == ["bundle_path", "created_at", "id", "object", "params_json", "scope_json", "updated_at"])
    try store.migrate(to: nil)
    #expect(try store.columnNames(of: "stacks").contains("status"))
    #expect(try store.stacks().map(\.bundlePath) == ["stacks/A"])
    #expect(try store.pausedStacks().isEmpty)
  }
}
