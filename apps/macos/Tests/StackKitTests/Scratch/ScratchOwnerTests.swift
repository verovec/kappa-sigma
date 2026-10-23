import Foundation
import StackKit
import TestSupport
import Testing

@Suite("ScratchOwner — who owns a scratch folder, and whether it still runs")
struct ScratchOwnerTests {
  /// One row: the owner recorded in the marker, and what the process table now says of its pid.
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let recorded: ProcessIdentity
    let running: ProcessIdentity?
    let alive: Bool
    var testDescription: String { name }
  }

  static let owner = ProcessIdentity(pid: 4242, startSeconds: 1_792_616_400, startMicroseconds: 7)

  static let cases = [
    Case(name: "its pid runs, started then", recorded: owner, running: owner, alive: true),
    Case(name: "no process has its pid", recorded: owner, running: nil, alive: false),
    Case(
      name: "its pid was reused by a later process", recorded: owner,
      running: ProcessIdentity(pid: 4242, startSeconds: 1_792_620_000, startMicroseconds: 7),
      alive: false),
  ]

  @Test("an owner is alive only while its pid runs with the start time recorded", arguments: cases)
  func testIsAlive(_ row: Case) {
    let table = FakeProcessTable(running: row.running.map { [$0] } ?? [])
    #expect(ScratchOwner(owner: row.recorded).isAlive(in: table.table) == row.alive)
  }

  @Test("this process is alive by its own marker", .scratchDirectory)
  func testOwnMarkerIsAlive() throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("run_x", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try ScratchOwner.mark(folder)
    let marker = try #require(ScratchOwner.read(folder))
    #expect(marker.owner.pid == getpid())
    #expect(marker.siril == nil)
    #expect(marker.isAlive(in: .live))
  }

  @Test("a folder without a marker has no owner to ask", .scratchDirectory)
  func testUnmarkedFolder() throws {
    #expect(ScratchOwner.read(try ScratchDirectory.url) == nil)
  }

  @Test("the Siril it launched is recorded next to the owner", .scratchDirectory)
  func testRecordsSiril() throws {
    let folder = try ScratchDirectory.url
    let siril = ProcessIdentity(pid: 99, startSeconds: 5, startMicroseconds: 0)
    let table = FakeProcessTable(running: [siril])
    try ScratchOwner.mark(folder)
    try ScratchOwner.recordSiril(pid: 99, in: folder, table: table.table)
    #expect(ScratchOwner.read(folder)?.siril == siril)
    #expect(ScratchOwner.read(folder)?.owner.pid == getpid(), "the owner is kept")
  }
}
