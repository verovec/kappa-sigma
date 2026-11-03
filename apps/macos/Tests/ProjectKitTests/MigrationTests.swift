import Foundation
import ProjectKit
import TestSupport
import Testing

/// Schema changes of the bundled migrations, one test per change that reshapes rows.
@Suite("Migrations — rows kept through a table rebuild")
struct MigrationTests {
  @Test(
    "0009: exports gain remote_url/remote_status/remote_error, folder nullable; down restores 0006",
    .scratchDirectory)
  func testExportsRemoteColumns() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "RGB")
    let local = try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: nil, folder: "/tmp/out",
      settingsJSON: "{}", files: ["final.png"])
    let remote = try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: nil, folder: nil, settingsJSON: "{}",
      files: ["final.tif"], remoteURL: "s3://b/p/final", remoteStatus: .done)
    let failed = try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: nil, folder: "/tmp/out2",
      settingsJSON: "{}", files: ["final.tif"], remoteURL: "s3://b/p/2", remoteStatus: .failed,
      remoteError: "S3 500 InternalError: boom", remoteConnection: "conn-1")
    #expect(try store.exports(stackID: stack.id).first?.remoteConnection == "conn-1")
    #expect(remote.folder == nil && failed.remoteError == "S3 500 InternalError: boom")
    #expect(
      try store.columnNames(of: "exports") == [
        "created_at", "files_json", "folder", "head_step_id", "id", "image_id",
        "remote_connection", "remote_error", "remote_status", "remote_url", "settings_json",
        "stack_id", "updated_at",
      ])
    try store.setRemoteStatus(exportID: failed.id, .done, error: nil)
    let resent = try #require(try store.exports(stackID: stack.id).first { $0.id == failed.id })
    #expect(resent.remoteStatus == .done && resent.remoteError == nil)

    try store.migrate(to: 8)

    #expect(
      try store.columnNames(of: "exports") == [
        "created_at", "files_json", "folder", "head_step_id", "id", "image_id", "settings_json",
        "stack_id", "updated_at",
      ])
    #expect(try store.indexNames(of: "exports").count == 3)
    #expect(
      try store.exports(stackID: stack.id).map(\.id) == [failed.id, local.id],
      "down keeps the rows with a folder; an S3-only row has no 0006 shape and goes")

    try store.migrate(to: 9)

    #expect(
      try store.indexNames(of: "exports") == [
        "exports_head_step_id", "exports_image_id", "exports_stack_id",
      ])
    let rows = try store.exports(stackID: stack.id)
    #expect(rows.map(\.folder) == ["/tmp/out2", "/tmp/out"])
    #expect(rows.allSatisfy { $0.remoteStatus == .none && $0.remoteURL == nil }, "up: 'none'")
  }

  @Test(
    "0010: sources take a remote night (connection, bucket, prefix); down drops them and its scans",
    .scratchDirectory)
  func testRemoteSources() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let night = try store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    try store.setProfile("osc-dualband", kind: .night, path: "/captures/M31/2026-10-18")
    // A stack points at the night: the rebuild drops a table its rows reference (RESTRICT).
    let stack = try store.addStack(bundlePath: "stacks/A", sourceIDs: [night.id], paramsJSON: "{}")

    let remote = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "nights/M31/")

    #expect(remote.kind == .remoteNight && remote.path == "s3://astro/nights/M31")
    #expect(remote.connectionID == "conn-1" && remote.bucket == "astro")
    #expect(remote.prefix == "nights/M31")
    #expect(
      try store.columnNames(of: "sources") == [
        "bucket", "connection_id", "created_at", "id", "kind", "path", "prefix", "profile_id",
        "read_only", "updated_at",
      ])
    let kept = try #require(try store.sources().first { $0.id == night.id })
    #expect(kept.path == "/captures/M31/2026-10-18" && kept.profileID == "osc-dualband")
    #expect(kept.bucket == nil && kept.prefix == nil && kept.connectionID == nil)
    #expect(try store.stack(id: stack.id)?.sourceIDs == [night.id])
    #expect(try store.foreignKeyViolations().isEmpty, "the rebuild left no orphan link")

    try store.migrate(to: 9)

    #expect(
      try store.columnNames(of: "sources") == [
        "created_at", "id", "kind", "path", "profile_id", "read_only", "updated_at",
      ])
    #expect(
      try store.sources().map(\.path) == ["/captures/M31/2026-10-18"],
      "down keeps the local nights; a remote one has no 0004 shape and goes")
    #expect(try store.sources().first?.profileID == "osc-dualband")
    #expect(try !store.tableNames().contains("remote_scans"))
    #expect(try store.stack(id: stack.id)?.sourceIDs == [night.id])

    try store.migrate(to: nil)

    #expect(try store.sources().map(\.path) == ["/captures/M31/2026-10-18"], "up: the night stays")
    #expect(try store.stack(id: stack.id)?.sourceIDs == [night.id], "its stack link survived both")
    #expect(try store.foreignKeyViolations().isEmpty, "neither direction orphans a row")
  }

  @Test(
    "0007's down still cascades: a paused stack with sources leaves no orphan link",
    .scratchDirectory)
  func testPausedStackDownCascades() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let night = try store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    try store.addStack(
      bundlePath: "stacks/paused", sourceIDs: [night.id], paramsJSON: "{}", status: .paused,
      checkpointJSON: "{}")

    // 0007's down deletes the paused stacks and relies on ON DELETE CASCADE for their links: a
    // migrator that ran with foreign keys off would leave them behind (card 0168 keeps them on,
    // 0010 sets its own links aside instead).
    try store.migrate(to: 6)

    #expect(try store.foreignKeyViolations().isEmpty, "the cascade fired: no orphan stack_sources")
    try store.migrate(to: nil)
    #expect(try store.pausedStacks().isEmpty, "the paused stack went with the downgrade")
    #expect(try store.sources().map(\.id) == [night.id], "its night stayed")
  }
}
