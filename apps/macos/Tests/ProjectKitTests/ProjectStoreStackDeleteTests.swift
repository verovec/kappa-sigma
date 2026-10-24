import Foundation
import ProjectKit
import TestSupport
import Testing

/// Deleting a stack (card 0114): its rows in one transaction, snapshots first (their step is
/// `ON DELETE RESTRICT`), then its folder in `stacks/`; the stack open in the Studio is refused.
@Suite("ProjectStore: deleting a stack and when it was last opened (0008_stack_opened_at)")
struct ProjectStoreStackDeleteTests {
  /// A stack with an image, two steps, a snapshot on the first and an export, its folder filled.
  static func filledStack(_ store: ProjectStore, package: URL, name: String) throws
    -> ProjectStack
  {
    let night = try store.addSource(kind: .night, path: "/captures/M31")
    let stack = try store.addStack(
      bundlePath: "stacks/\(name)", sourceIDs: [night.id], paramsJSON: "{}", imageRoles: ["RGB"])
    let image = try #require(try store.images(stackID: stack.id).first)
    let first = try store.appendHistoryStep(
      imageID: image.id, processID: "stretch", paramsJSON: "{}",
      output: .init(path: "stacks/\(name)/history/1.fits", bytes: 10), contentHash: nil)
    _ = try store.appendHistoryStep(
      imageID: image.id, processID: "curves", paramsJSON: "{}", output: nil, contentHash: nil)
    try store.addSnapshot(imageID: image.id, name: "before curves", stepID: first.id)
    try store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: first.id, folder: "/tmp/out",
      settingsJSON: "{}", files: ["final.png"])
    let history = package.appendingPathComponent("stacks/\(name)/history", isDirectory: true)
    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    try Data(count: 32).write(to: history.appendingPathComponent("1.fits"))
    return stack
  }

  static func exists(_ path: String, in package: URL) -> Bool {
    FileManager.default.fileExists(atPath: package.appendingPathComponent(path).path)
  }

  @Test("every row of the stack goes, then its folder; another stack stays", .scratchDirectory)
  func testDeleteStackCascades() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try Self.filledStack(store, package: package.url, name: "A")
    let other = try Self.filledStack(store, package: package.url, name: "B")
    let image = try #require(try store.images(stackID: stack.id).first)

    try store.deleteStack(id: stack.id, packageFolder: package.url, openStackID: other.id)

    #expect(try store.stack(id: stack.id) == nil)
    #expect(try store.images(stackID: stack.id).isEmpty)
    #expect(try store.history(imageID: image.id).isEmpty)
    #expect(try store.snapshots(imageID: image.id).isEmpty)
    #expect(try store.exports(stackID: stack.id).isEmpty)
    #expect(!Self.exists("stacks/A", in: package.url))
    #expect(try store.stacks().map(\.id) == [other.id])
    #expect(try store.exports(stackID: other.id).count == 1)
    #expect(Self.exists("stacks/B", in: package.url))
  }

  @Test("the stack open in the Studio is refused: nothing deleted", .scratchDirectory)
  func testRefusesOpenStack() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try Self.filledStack(store, package: package.url, name: "A")
    #expect(throws: ProjectStoreError.stackOpen(stackID: stack.id)) {
      try store.deleteStack(id: stack.id, packageFolder: package.url, openStackID: stack.id)
    }
    #expect(try store.stack(id: stack.id) != nil)
    #expect(Self.exists("stacks/A", in: package.url))
  }

  @Test(
    "a bundle path outside stacks/ loses its rows, never its folder",
    .scratchDirectory,
    arguments: ["../outside", "stacks/../..", "stacks", "/tmp/run", "stacks/a/b"])
  func testForeignFolderKept(_ path: String) throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: path, sourceIDs: [], paramsJSON: "{}")
    let marker = try ScratchDirectory.url.appendingPathComponent("outside/keep.txt")
    try FileManager.default.createDirectory(
      at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: marker)
    try store.deleteStack(id: stack.id, packageFolder: package.url, openStackID: nil)
    #expect(try store.stack(id: stack.id) == nil)
    #expect(FileManager.default.fileExists(atPath: marker.path))
    #expect(FileManager.default.fileExists(atPath: package.url.path))
  }

  @Test("an unknown stack is a no-op", .scratchDirectory)
  func testUnknownStack() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    try package.store.deleteStack(id: 42, packageFolder: package.url, openStackID: nil)
  }

  @Test(
    "opening a stack records when; exports are counted per stack; down to 0007 drops the column",
    .scratchDirectory)
  func testOpenedAtAndExportCounts() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try Self.filledStack(store, package: package.url, name: "A")
    let bare = try store.addStack(bundlePath: "stacks/B", sourceIDs: [], paramsJSON: "{}")
    #expect(stack.openedAt == nil)
    try store.markStackOpened(id: stack.id)
    let marked = try #require(try store.stack(id: stack.id))
    let opened = try #require(marked.openedAt)
    #expect(opened >= stack.createdAt && marked.updatedAt == opened, "a write bumps updated_at")
    #expect(try store.exportCounts() == [stack.id: 1])
    #expect(try store.stack(id: bare.id)?.openedAt == nil)

    try store.migrate(to: 7)
    #expect(try !store.columnNames(of: "stacks").contains("opened_at"))
    try store.migrate(to: nil)
    #expect(try store.columnNames(of: "stacks").contains("opened_at"))
  }

  @Test(
    "a folder that resists the delete: the rows go, no error, the folder stays",
    .scratchDirectory)
  func testFolderThatResists() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try Self.filledStack(store, package: package.url, name: "A")
    let locked = package.url.appendingPathComponent("stacks/A/history")
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
    }
    try store.deleteStack(id: stack.id, packageFolder: package.url, openStackID: nil)
    #expect(try store.stack(id: stack.id) == nil)
    #expect(Self.exists("stacks/A/history/1.fits", in: package.url))
  }

  @Test("the usage of a closed package is read read-only, with the chosen stack", .scratchDirectory)
  func testReadUsage() throws {
    let package = try ProjectStoreTests.newPackage()
    let stack = try Self.filledStack(package.store, package: package.url, name: "A")
    try package.store.setSetting("workspace.stack", to: String(stack.id))
    try package.store.keepStacks([7])
    try package.store.keepStacks([3, 7])
    try package.close()
    let usage = try #require(
      try ProjectPackage.readUsage(at: package.url, chosenKey: "workspace.stack"))
    #expect(usage.stacks.map(\.id) == [stack.id])
    #expect(usage.exportCounts == [stack.id: 1] && usage.chosenStackID == stack.id)
    #expect(usage.keptStackIDs == [3, 7] && usage.protected == [3, 7, stack.id])

    let reopened = try ProjectPackage.open(at: package.url)
    try reopened.store.migrate(to: 7)
    try reopened.close()
    #expect(try ProjectPackage.readUsage(at: package.url, chosenKey: "workspace.stack") == nil)
  }
}
