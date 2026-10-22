import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("ProjectStore: the exports a project wrote (card 0091)")
struct ExportsStoreTests {
  @Test(
    "an export is recorded per stack, newest first, counted; down to 0005 drops the table",
    .scratchDirectory)
  func testExportsUpDown() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}")
    let other = try store.addStack(bundlePath: "stacks/B", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "RGB")
    let step = try store.appendHistoryStep(
      imageID: image.id, processID: "stretch", paramsJSON: "{}", output: nil, contentHash: nil)
    #expect(try store.exports(stackID: stack.id).isEmpty)

    let first = try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: step.id, folder: "/tmp/out/1",
      settingsJSON: #"{"formats":["png16"]}"#, files: ["final.png", "final-starless.png"])
    let second = try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: nil, folder: "/tmp/out/2",
      settingsJSON: "{}", files: ["final.fits"])
    #expect(first.headStepID == step.id && first.files == ["final.png", "final-starless.png"])
    #expect(try store.exports(stackID: stack.id) == [second, first])
    #expect(try store.exports(stackID: other.id).isEmpty)
    #expect(try store.summary().exports == 2)

    try store.migrate(to: 5)
    #expect(try !store.tableNames().contains("exports"))
    try store.migrate(to: nil)
    #expect(try store.appliedMigrations().last?.name == "exports")
    #expect(
      try store.columnNames(of: "exports") == [
        "created_at", "files_json", "folder", "head_step_id", "id", "image_id", "settings_json",
        "stack_id", "updated_at",
      ])
    #expect(try store.exports(stackID: stack.id).isEmpty)
  }

  @Test(
    "an export goes with its stack; a deleted head step leaves the row without it",
    .scratchDirectory)
  func testExportsFollowTheirRows() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "RGB")
    let step = try store.appendHistoryStep(
      imageID: image.id, processID: "stretch", paramsJSON: "{}", output: nil, contentHash: nil)
    try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: step.id, folder: "/tmp/out",
      settingsJSON: "{}", files: [])

    try store.deleteHistoryStep(id: step.id)
    #expect(try store.exports(stackID: stack.id).map(\.headStepID) == [nil])
  }
}
