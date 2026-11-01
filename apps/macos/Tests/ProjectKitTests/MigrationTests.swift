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
}
