import Foundation
import ProjectKit
import TestSupport
import Testing

/// One owner per project (card 0147): `open` writes who holds the package, `close` removes it; a
/// live owner elsewhere refuses the open with its pid, a stale one (a crash) is replaced, this
/// process is always accepted, a short opener owns nothing, a copy carries no owner.
extension ProjectPackageTests {
  @Test(
    "testOpen_writesAndRemovesOwner: open marks the package with this process, close unmarks",
    .scratchDirectory)
  func testOpen_writesAndRemovesOwner() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try ProjectPackage.create(at: url).close()
    #expect(ProjectOwner.read(in: url) == nil, "a created-and-closed package has no owner")
    let package = try ProjectPackage.open(at: url)
    let owner = try #require(ProjectOwner.read(in: url))
    #expect(owner.process == ProcessLiveness.current)
    try package.close()
    #expect(ProjectOwner.read(in: url) == nil)
  }

  struct Marker: CustomTestStringConvertible, Sendable {
    let name: String
    let process: ProcessStamp?
    let refused: Bool
    var testDescription: String { name }
  }

  static let markers: [Marker] = [
    Marker(
      name: "a live owner elsewhere (the test runner, our parent) refuses",
      process: ProcessLiveness.stamp(of: getppid()),
      refused: true),
    Marker(
      name: "a stale owner (a pid long gone) is replaced",
      process: ProcessStamp(pid: 999_999, startSeconds: 1, startMicroseconds: 0), refused: false),
    Marker(
      name: "this process reopens its own package (a move, a Save As)",
      process: ProcessLiveness.current, refused: false),
  ]

  @Test(
    "testOpen_refusesLiveOwner / testOpen_replacesStaleOwner", .scratchDirectory, arguments: markers
  )
  func testOpen_owners(row: Marker) throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try ProjectPackage.create(at: url).close()
    let process = try #require(row.process)
    try ProjectOwner(process: process).write(
      in: url)
    if row.refused {
      #expect(throws: ProjectPackageError.openElsewhere(path: url.path, pid: process.pid)) {
        try ProjectPackage.open(at: url)
      }
      #expect(ProjectOwner.read(in: url)?.process == process, "the other owner's marker is kept")
    } else {
      let package = try ProjectPackage.open(at: url)
      #expect(ProjectOwner.read(in: url)?.process == ProcessLiveness.current, "ours now")
      try package.close()
      #expect(ProjectOwner.read(in: url) == nil)
    }
  }

  @Test(
    "a short opener owns nothing: no marker written, the window's marker kept", .scratchDirectory)
  func testOpen_notOwning() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try ProjectPackage.create(at: url).close()
    let short = try ProjectPackage.open(at: url, owning: false)
    #expect(ProjectOwner.read(in: url) == nil)
    try short.closeKeepingWAL()
    let window = try ProjectPackage.open(at: url)
    let review = try ProjectPackage.open(at: url, owning: false)
    try review.closeKeepingWAL()
    #expect(ProjectOwner.read(in: url)?.process == ProcessLiveness.current, "the window still owns")
    try window.close()
  }

  @Test("a copy carries no owner; the summary never looks at the marker", .scratchDirectory)
  func testOwner_copyAndSummary() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    let copyURL = try ScratchDirectory.url.appendingPathComponent("Copy.astrostack")
    let package = try ProjectPackage.open(at: ProjectPackage.create(at: url).url)
    _ = try package.store.addSource(kind: .night, path: "/captures/P/2026-10-18")
    try package.copy(to: copyURL)
    #expect(ProjectOwner.read(in: copyURL) == nil)
    #expect(try ProjectPackage.readSummary(at: url).sources == 1)
    #expect(
      ProjectOwner.read(in: url)?.process == ProcessLiveness.current, "untouched by the summary")
    try package.close()
  }

  @Test("a live owner elsewhere is held; ours or a dead one is not", .scratchDirectory)
  func testOwner_heldElsewhere() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try ProjectPackage.create(at: url).close()
    try ProjectOwner(process: try #require(ProcessLiveness.current)).write(in: url)
    #expect(ProjectOwner.heldElsewhere(in: url) == nil, "ours is not elsewhere")
    try ProjectOwner(process: ProcessStamp(pid: 999_999, startSeconds: 1, startMicroseconds: 0))
      .write(in: url)
    #expect(ProjectOwner.heldElsewhere(in: url) == nil, "a dead owner holds nothing")
    let parent = try #require(ProcessLiveness.stamp(of: getppid()))
    try ProjectOwner(process: parent).write(in: url)
    #expect(ProjectOwner.heldElsewhere(in: url)?.process == parent)
  }

  @Test(
    "a reopen by this process keeps the newer token: the older instance's close removes nothing",
    .scratchDirectory)
  func testOwner_tokenPerOpening() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("P.astrostack")
    try ProjectPackage.create(at: url).close()
    let first = try ProjectPackage.open(at: url)
    let firstToken = try #require(ProjectOwner.read(in: url)?.token)
    // A reopen by this process (a move, a Save As, a revert) rewrites the marker with its token.
    let reopened = ProjectOwner(process: try #require(ProcessLiveness.current))
    try reopened.write(in: url)
    #expect(reopened.token != firstToken)
    try first.close()
    #expect(ProjectOwner.read(in: url)?.token == reopened.token, "the window keeps its marker")
    ProjectOwner.release(reopened.token, in: url)
    #expect(ProjectOwner.read(in: url) == nil)
  }
}
