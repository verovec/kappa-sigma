import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("ProjectPackage: the .astrostack folder and its project.db")
struct ProjectPackageTests {
  /// A closed package is its `project.db` and nothing else: no WAL or shared-memory file left.
  static func expectOnlyDatabase(
    in url: URL, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let items = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    #expect(items == ["project.db"], sourceLocation: sourceLocation)
  }

  @Test("a new package with an empty project.db opens, saves and reopens", .scratchDirectory)
  func testDocumentRoundTrip() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")

    let created = try ProjectPackage.create(at: url)
    try created.save()
    try created.close()
    try Self.expectOnlyDatabase(in: url)

    let reopened = try ProjectPackage.open(at: url)
    #expect(reopened.url == url)
    try reopened.save()
    try reopened.close()
    try Self.expectOnlyDatabase(in: url)
  }

  @Test("save as copies the package; the original stays as it was", .scratchDirectory)
  func testProjectPackage_copy_savesAs() throws {
    let scratch = try ScratchDirectory.url
    let original = try ProjectPackage.create(at: scratch.appendingPathComponent("A.astrostack"))
    let copyURL = scratch.appendingPathComponent("B.astrostack")

    try original.copy(to: copyURL)
    try original.close()

    let copy = try ProjectPackage.open(at: copyURL)
    try copy.close()
    try Self.expectOnlyDatabase(in: copyURL)
    try Self.expectOnlyDatabase(in: original.url)
  }

  @Test("a copy that fails halfway leaves nothing at the destination", .scratchDirectory)
  func testProjectPackage_copy_failureLeavesNothing() throws {
    let scratch = try ScratchDirectory.url
    let package = try ProjectPackage.create(at: scratch.appendingPathComponent("A.astrostack"))
    let unreadable = package.url.appendingPathComponent("unreadable.fits.txt")
    try Data("x".utf8).write(to: unreadable)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
      try? package.close()
    }
    let destination = scratch.appendingPathComponent("B.astrostack")

    #expect(throws: (any Error).self) { try package.copy(to: destination) }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
  }

  enum Layout: String, CaseIterable, Sendable {
    case nothing, plainFile, emptyFolder, foreignDatabase, notSQLite
  }

  static let openErrors: [(Layout, ProjectPackageError)] = [
    (.nothing, .notAPackage(path: "P.astrostack")),
    (.plainFile, .notAPackage(path: "P.astrostack")),
    (.emptyFolder, .missingDatabase(path: "P.astrostack")),
    (.foreignDatabase, .foreignDatabase(path: "P.astrostack")),
    (.notSQLite, .foreignDatabase(path: "P.astrostack")),
  ]

  @Test(
    "opening something that is not a project fails with a reason", .scratchDirectory,
    arguments: openErrors)
  func testProjectPackage_open_rejects(layout: Layout, expected: ProjectPackageError) throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try Self.make(layout, at: url)
    let error = #expect(throws: ProjectPackageError.self) { try ProjectPackage.open(at: url) }
    #expect(error?.relativeToFolder == expected)
  }

  @Test("a refused foreign database is left byte-identical, nothing added", .scratchDirectory)
  func testProjectPackage_open_foreignUntouched() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try Self.make(.foreignDatabase, at: url)
    let database = url.appendingPathComponent("project.db")
    let before = try Data(contentsOf: database)

    #expect(throws: ProjectPackageError.foreignDatabase(path: url.path)) {
      try ProjectPackage.open(at: url)
    }
    #expect(try Data(contentsOf: database) == before)
    try Self.expectOnlyDatabase(in: url)
  }

  @Test("creating over an existing path refuses to overwrite it", .scratchDirectory)
  func testProjectPackage_create_refusesExisting() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: ProjectPackageError.alreadyExists(path: url.path)) {
      try ProjectPackage.create(at: url)
    }
  }

  static func make(_ layout: Layout, at url: URL) throws {
    let manager = FileManager.default
    let database = url.appendingPathComponent("project.db")
    switch layout {
    case .nothing:
      break
    case .plainFile:
      try Data("x".utf8).write(to: url)
    case .emptyFolder:
      try manager.createDirectory(at: url, withIntermediateDirectories: false)
    case .foreignDatabase:
      try manager.createDirectory(at: url, withIntermediateDirectories: false)
      // SQLite reads a zero-length file as an empty database whose application_id is 0.
      try Data().write(to: database)
    case .notSQLite:
      try manager.createDirectory(at: url, withIntermediateDirectories: false)
      try Data(repeating: 0x41, count: 4096).write(to: database)
    }
  }
}

extension ProjectPackageError {
  /// The same error with its path reduced to the last component, so table rows stay readable.
  fileprivate var relativeToFolder: Self {
    switch self {
    case .notAPackage(let path): .notAPackage(path: (path as NSString).lastPathComponent)
    case .missingDatabase(let path): .missingDatabase(path: (path as NSString).lastPathComponent)
    case .foreignDatabase(let path): .foreignDatabase(path: (path as NSString).lastPathComponent)
    case .alreadyExists(let path): .alreadyExists(path: (path as NSString).lastPathComponent)
    case .openElsewhere(let path, let pid):
      .openElsewhere(path: (path as NSString).lastPathComponent, pid: pid)
    }
  }
}
