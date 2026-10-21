import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("ProjectPackage.readSummary: a project's counts read without opening it")
struct ProjectPackageSummaryTests {
  @Test("a closed package is counted and left byte for byte as it was", .scratchDirectory)
  func testClosedPackageUntouched() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M 31.astrostack")
    let package = try ProjectPackage.create(at: url)
    _ = try package.store.addSource(kind: .night, path: "/captures/M31/2026-09-22")
    try package.save()
    try package.close()
    let database = url.appendingPathComponent("project.db")
    let before = try Data(contentsOf: database)

    let summary = try ProjectPackage.readSummary(at: url)

    #expect(summary.sources == 1)
    #expect(try Data(contentsOf: database) == before)
    try ProjectPackageTests.expectOnlyDatabase(in: url)
  }

  @Test("a package open elsewhere is counted without touching its WAL", .scratchDirectory)
  func testOpenPackageKeepsItsWAL() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("IC 1848.astrostack")
    let package = try ProjectPackage.create(at: url)
    _ = try package.store.addSource(kind: .night, path: "/captures/IC1848/2026-10-18")
    let wal = url.appendingPathComponent("project.db-wal")
    #expect(FileManager.default.fileExists(atPath: wal.path))

    let summary = try ProjectPackage.readSummary(at: url)

    #expect(summary.sources == 1)
    #expect(FileManager.default.fileExists(atPath: wal.path))
    _ = try package.store.addSource(kind: .night, path: "/captures/IC1848/2026-10-19")
    #expect(try package.store.summary().sources == 2)
    try package.close()
  }

  @Test("a folder AstroStack did not create is refused", .scratchDirectory)
  func testForeignDatabaseRefused() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("Other.astrostack")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: url.appendingPathComponent("project.db"))

    #expect(throws: ProjectPackageError.foreignDatabase(path: url.path)) {
      try ProjectPackage.readSummary(at: url)
    }
  }
}
