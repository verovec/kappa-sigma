import AstroStackApp
import Foundation
import ProjectKit
import StackKit
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

  @Test(
    "a library its permissions refuse throws « cannot be read », never empty", .scratchDirectory)
  func testUnreadableLibraryThrows() async throws {
    let project = try Self.project()
    defer { try? project.close() }
    let library = try ScratchDirectory.url.appendingPathComponent("library")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: library.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
    }
    await #expect(throws: CalibrationError.unreadableLibrary(library.path)) {
      try await LibraryIndex(store: project.store, folder: library).masters()
    }
  }

  @Test("a privacy refusal (EPERM) says where to allow it; EACCES is the library's own error")
  func testRefusalKinds() {
    func listing(_ posix: Int32) -> NSError {
      NSError(
        domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue,
        userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(posix))])
    }
    let path = "/Users/me/Documents/astro/library"
    #expect(
      LibraryIndex.refusal(listing(EPERM), path: path) as? UserFacingError
        == .documentsAccess(path: path))
    #expect(
      LibraryIndex.refusal(listing(EACCES), path: path) as? CalibrationError
        == .unreadableLibrary(path))
    let sentence = UserFacingError.documentsAccess(path: path).message
    #expect(sentence.text("en").contains(path) && sentence.text("en").contains("Files and Folders"))
    #expect(sentence.text("fr").contains("Fichiers et dossiers"))
  }
}
