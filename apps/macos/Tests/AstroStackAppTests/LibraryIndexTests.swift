import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

/// The calibration library is absent (every master is one the capture builds), readable (indexed),
/// or unreadable — and an unreadable one is an error naming the folder, never an empty library
/// (R2: no silent fallback to « build every master »).
@Suite("LibraryIndex — absent, readable or refused, never silently empty", .serialized)
struct LibraryIndexTests {
  static func project() throws -> ProjectPackage {
    try ProjectPackage.create(at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
  }

  @Test("an absent library gives no master; a readable one is indexed", .scratchDirectory)
  func testAbsentAndReadable() async throws {
    let project = try Self.project()
    defer { try? project.close() }
    let library = try ScratchDirectory.url.appendingPathComponent("library")
    #expect(try await LibraryIndex(store: project.store, folder: library).masters().isEmpty)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try Data("bias".utf8).write(to: library.appendingPathComponent("master_BIAS_g100o50_b1.fits"))
    let masters = try await LibraryIndex(store: project.store, folder: library).masters()
    #expect(masters.count == 1)
  }

  @Test("a library the app may not read throws the access error naming it", .scratchDirectory)
  func testUnreadableLibraryThrows() async throws {
    let project = try Self.project()
    defer { try? project.close() }
    let library = try ScratchDirectory.url.appendingPathComponent("library")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: library.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
    }
    await #expect(throws: UserFacingError.documentsAccess(path: library.path)) {
      try await LibraryIndex(store: project.store, folder: library).masters()
    }
    let sentence = UserFacingError.documentsAccess(path: library.path).message
    #expect(
      sentence.text("en").contains(library.path)
        && sentence.text("en").contains("Files and Folders"))
    #expect(sentence.text("fr").contains("Fichiers et dossiers"))
  }
}
