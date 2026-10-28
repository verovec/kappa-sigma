import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

@MainActor
@Suite("ProjectDocument: the NSDocument over a .astrostack package")
struct ProjectDocumentTests {
  static let type = ProjectPackage.typeIdentifier

  @Test("an untitled document owns a temporary package until its first save", .scratchDirectory)
  func testProjectDocument_firstSave_movesUntitledPackage() throws {
    let target = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let document = try ProjectDocument(type: Self.type)
    let untitled = try #require(document.packageURL)
    #expect(FileManager.default.fileExists(atPath: untitled.path))

    try document.writeSafely(to: target, ofType: Self.type, for: .saveOperation)

    #expect(document.packageURL == target)
    #expect(!FileManager.default.fileExists(atPath: untitled.path))
    document.close()
    #expect(try ProjectPackage.open(at: target).url == target)
  }

  @Test("an untitled package sits in a folder this process marks; closing removes both")
  func testProjectDocument_untitled_markedAndRemoved() throws {
    let document = try ProjectDocument(type: Self.type)
    let untitled = try #require(document.packageURL)
    let folder = untitled.deletingLastPathComponent()
    #expect(folder.deletingLastPathComponent().lastPathComponent == "Untitled")
    #expect(ScratchOwner.read(folder)?.owner.pid == getpid(), "a crash leaves it to the sweep")
    #expect(
      !FileManager.default.fileExists(
        atPath: untitled.appendingPathComponent(ScratchOwner.fileName).path),
      "never inside the package a Save copies")

    document.close()

    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test("saving onto its own file saves in place; reopening works", .scratchDirectory)
  func testProjectDocument_save_inPlace() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    #expect(document.packageURL == url)

    try document.writeSafely(to: url, ofType: Self.type, for: .saveOperation)
    document.close()

    let reopened = try ProjectDocument(contentsOf: url, ofType: Self.type)
    #expect(reopened.packageURL == url)
    reopened.close()
  }

  @Test("save as moves the document to the copy; save to leaves it in place", .scratchDirectory)
  func testProjectDocument_saveAs_and_saveTo() throws {
    let scratch = try ScratchDirectory.url
    let original = scratch.appendingPathComponent("A.astrostack")
    try ProjectPackage.create(at: original).close()
    let document = try ProjectDocument(contentsOf: original, ofType: Self.type)

    let exported = scratch.appendingPathComponent("Export.astrostack")
    try document.writeSafely(to: exported, ofType: Self.type, for: .saveToOperation)
    #expect(document.packageURL == original)

    let moved = scratch.appendingPathComponent("B.astrostack")
    try document.writeSafely(to: moved, ofType: Self.type, for: .saveAsOperation)
    #expect(document.packageURL == moved)
    document.close()

    for url in [original, exported, moved] {
      try ProjectPackage.open(at: url).close()
    }
  }

  @Test(
    "save to and autosave operations write a copy; the document stays where it is",
    .scratchDirectory,
    arguments: [
      NSDocument.SaveOperationType.saveToOperation, .autosaveElsewhereOperation,
      .autosaveAsOperation,
    ])
  func testProjectDocument_copyOperations_keepDocument(
    _ operation: NSDocument.SaveOperationType
  ) throws {
    let scratch = try ScratchDirectory.url
    let original = scratch.appendingPathComponent("A.astrostack")
    try ProjectPackage.create(at: original).close()
    let document = try ProjectDocument(contentsOf: original, ofType: Self.type)

    let copy = scratch.appendingPathComponent("Copy.astrostack")
    try document.writeSafely(to: copy, ofType: Self.type, for: operation)

    #expect(document.packageURL == original)
    document.close()
    try ProjectPackage.open(at: copy).close()
  }

  @Test(
    "Save on a titled project saves in place, even when AppKit names another path",
    .scratchDirectory)
  func testProjectDocument_save_neverCopiesTitledProject() throws {
    let scratch = try ScratchDirectory.url
    let url = scratch.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)

    // After a move in the Finder, NSDocument's fileURL differs from the path opened at first.
    let moved = scratch.appendingPathComponent("Moved.astrostack")
    try document.writeSafely(to: moved, ofType: Self.type, for: .saveOperation)

    #expect(!FileManager.default.fileExists(atPath: moved.path))
    document.close()
  }

  @Test(
    "a project moved in the Finder while open reopens at its new place on Save",
    .scratchDirectory)
  func testProjectDocument_save_followsMovedPackage() throws {
    let scratch = try ScratchDirectory.url
    let original = scratch.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: original).close()
    let document = try ProjectDocument(contentsOf: original, ofType: Self.type)

    let moved = scratch.appendingPathComponent("Moved.astrostack")
    try FileManager.default.moveItem(at: original, to: moved)
    try document.writeSafely(to: moved, ofType: Self.type, for: .saveOperation)

    #expect(document.packageURL == moved)
    document.close()
    #expect(!FileManager.default.fileExists(atPath: original.path))
    let items = try FileManager.default.contentsOfDirectory(atPath: moved.path)
    #expect(items == ["project.db"])
  }

  @Test("when AppKit reports the move (fileURL), the package reopens at once", .scratchDirectory)
  func testProjectDocument_fileURL_followsMove() throws {
    let scratch = try ScratchDirectory.url
    let original = scratch.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: original).close()
    let document = try ProjectDocument(contentsOf: original, ofType: Self.type)

    let moved = scratch.appendingPathComponent("Moved.astrostack")
    try FileManager.default.moveItem(at: original, to: moved)
    document.fileURL = moved

    #expect(document.packageURL == moved)
    document.close()
    #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path) == ["project.db"])
  }

  @Test("reading again (revert) closes the package opened before", .scratchDirectory)
  func testProjectDocument_revert_closesPreviousPackage() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)

    try document.read(from: url, ofType: Self.type)
    document.close()

    let items = try FileManager.default.contentsOfDirectory(atPath: url.path)
    #expect(items == ["project.db"])
  }

  @Test("reading a file into an untitled document deletes its temporary package")
  func testProjectDocument_read_deletesUntitledPackage() throws {
    let document = try ProjectDocument(type: Self.type)
    let untitled = try #require(document.packageURL)
    let url = untitled.deletingLastPathComponent()
      .appendingPathComponent("Read-\(UUID().uuidString).astrostack")
    try ProjectPackage.create(at: url).close()
    defer { try? FileManager.default.removeItem(at: url) }

    try document.read(from: url, ofType: Self.type)

    #expect(!FileManager.default.fileExists(atPath: untitled.path))
    document.close()
  }

  @Test("saving over an existing package replaces it", .scratchDirectory)
  func testProjectDocument_saveAs_replacesExisting() throws {
    let scratch = try ScratchDirectory.url
    let target = scratch.appendingPathComponent("Old.astrostack")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let document = try ProjectDocument(type: Self.type)

    try document.writeSafely(to: target, ofType: Self.type, for: .saveAsOperation)
    document.close()

    try ProjectPackage.open(at: target).close()
  }

  @Test("the window is titled after the file", .scratchDirectory)
  func testProjectDocument_window_titledAfterFile() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    document.makeWindowControllers()

    let window = try #require(document.windowControllers.first?.window)
    #expect(window.title.hasPrefix("M31"))
    document.close()
  }

  @Test(
    "testProjectDocument_read_openElsewhereMessage: a package another instance holds says so",
    .scratchDirectory)
  func testProjectDocument_read_openElsewhereMessage() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    // The parent (the test runner) stands for the other running AstroStack.
    let other = try #require(ProcessLiveness.stamp(of: getppid()))
    try ProjectOwner(process: other, bundlePath: "/Applications/AstroStack.app", startedAtMs: 1)
      .write(in: url)
    let error = #expect(throws: (any Error).self) {
      try ProjectDocument(contentsOf: url, ofType: Self.type)
    }
    let message = error?.localizedDescription ?? ""
    #expect(
      message.contains("another instance of AstroStack") || message.contains("autre instance"))
    #expect(message.contains(url.path))
    #expect(ProjectOwner.read(in: url)?.process == other, "the other owner keeps its marker")
  }

  @Test("the project owner marker is not the scratch owner's file: the sweep never meets it")
  func testOwnerMarkerNames() {
    #expect(ProjectOwner.fileName != ScratchOwner.fileName)
  }
}
