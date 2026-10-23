import Foundation
import StackKit
import TestSupport
import Testing

@Suite("LeftoverSweep — what a dead run or test leaves is removed, nothing else")
struct LeftoverSweepTests {
  static let now = Date(timeIntervalSince1970: 1_792_616_400)
  static let me = ProcessIdentity(pid: 10, startSeconds: 100, startMicroseconds: 0)
  static let dead = ProcessIdentity(pid: 11, startSeconds: 100, startMicroseconds: 0)
  static let siril = ProcessIdentity(pid: 12, startSeconds: 200, startMicroseconds: 0)

  /// A folder `name` under `root` holding one file, marked by `owner` (unmarked when `nil`) and
  /// last modified `age` seconds before `now`.
  static func folder(
    _ name: String, in root: URL, owner: ScratchOwner? = nil, age: TimeInterval = 60
  ) throws -> URL {
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 4096).write(to: folder.appendingPathComponent("r_pp_light_00001.fit"))
    if let owner { try owner.write(to: folder) }
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: folder.path)
    return folder
  }

  static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  @Test(
    "a dead owner's folder goes, a live one's stays, an unmarked one only after a day",
    .scratchDirectory)
  func testSweepsOnlyDeadOwners() throws {
    let scratch = try ScratchDirectory.url
    let work = scratch.appendingPathComponent("Work", isDirectory: true)
    let live = try Self.folder("run_live", in: work, owner: ScratchOwner(owner: Self.me))
    let gone = try Self.folder("run_dead", in: work, owner: ScratchOwner(owner: Self.dead))
    let fresh = try Self.folder("run_fresh", in: work, age: 3600)
    let stale = try Self.folder("run_stale", in: work, age: LeftoverSweep.staleAge + 60)
    // Not a run's folder: the root's filter leaves it, dead owner and age notwithstanding.
    let starnet = try Self.folder(
      "starnet", in: work, owner: ScratchOwner(owner: Self.dead), age: LeftoverSweep.staleAge * 2)
    // Outside every root.
    let outside = try Self.folder(
      "run_other", in: scratch, owner: ScratchOwner(owner: Self.dead))
    let processes = FakeProcessTable(running: [Self.me])

    let removed = LeftoverSweep(
      roots: [.init(folder: work, prefix: "run_")], table: processes.table, now: Self.now
    ).run()

    #expect(Self.exists(live) && Self.exists(fresh) && Self.exists(starnet))
    #expect(Self.exists(outside))
    #expect(!Self.exists(gone) && !Self.exists(stale))
    #expect(Set(removed.map(\.path.lastPathComponent)) == ["run_dead", "run_stale"])
    #expect(removed.allSatisfy { $0.bytes >= 4096 }, "each removal says what it freed")
    #expect(processes.terminatedPIDs.isEmpty, "no Siril recorded, none signalled")
  }

  @Test("a root under the astro data folder is refused, even when passed", .scratchDirectory)
  func testRefusesProtectedRoots() throws {
    let astro = try ScratchDirectory.url.appendingPathComponent("astro", isDirectory: true)
    let captures = astro.appendingPathComponent("captures", isDirectory: true)
    let night = try Self.folder(
      "run_M31", in: captures, owner: ScratchOwner(owner: Self.dead), age: 1e7)
    let sweep = LeftoverSweep(
      roots: [
        .init(folder: captures, prefix: "run_"), .init(folder: astro, prefix: ""),
        // Around it: its parent's unmarked, old « astro » entry would otherwise go.
        .init(folder: astro.deletingLastPathComponent(), prefix: ""),
      ],
      table: FakeProcessTable(running: []).table, now: Self.now, protected: [astro])

    #expect(sweep.run().isEmpty)
    #expect(Self.exists(night))
    #expect(
      LeftoverSweep.dataFolder.path.hasSuffix("/Documents/astro"),
      "~/Documents/astro is protected by default (R7)")
    #expect(
      LeftoverSweep(roots: [], table: FakeProcessTable(running: []).table)
        .protected == [LeftoverSweep.dataFolder])
  }

  @Test(
    "a dead owner's Siril is terminated, never a pid now running another program",
    .scratchDirectory,
    arguments: [
      ("/Applications/Siril.app/Contents/MacOS/siril-cli", true),
      ("/opt/homebrew/bin/siril-cli", true),
      ("/System/Applications/Mail.app/Contents/MacOS/Mail", false),
      ("/usr/local/bin/not-siril-cli", false),
    ])
  func testKillsOrphanSirilOnly(_ executable: String, signalled: Bool) throws {
    let root = try ScratchDirectory.url
    let marker = ScratchOwner(owner: Self.dead, siril: Self.siril)
    let fifo = try Self.folder("siril-ABC", in: root, owner: marker)
    let processes = FakeProcessTable(running: [Self.siril], executable: executable)

    _ = LeftoverSweep(
      roots: [.init(folder: root, prefix: "siril-")], table: processes.table, now: Self.now
    ).run()

    #expect(processes.terminatedPIDs == (signalled ? [Self.siril.pid] : []))
    #expect(Self.exists(fifo) == !signalled, "a Siril left running keeps its folder")
  }

  @Test("a plain file left in a root goes after a day like an unmarked folder", .scratchDirectory)
  func testStaleFilesSwept() throws {
    let root = try ScratchDirectory.url
    let (old, recent) = (
      root.appendingPathComponent("old.fit"), root.appendingPathComponent("new.fit")
    )
    for (file, age) in [(old, LeftoverSweep.staleAge + 60), (recent, 60)] {
      try Data(count: 16).write(to: file)
      try FileManager.default.setAttributes(
        [.modificationDate: Self.now.addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    _ = LeftoverSweep(
      roots: [.init(folder: root, prefix: "")], table: FakeProcessTable(running: []).table,
      now: Self.now
    ).run()

    #expect(!Self.exists(old) && Self.exists(recent))
  }

  @Test("a recorded Siril pid reused by a later Siril is never signalled", .scratchDirectory)
  func testReusedSirilPIDNotSignalled() throws {
    let root = try ScratchDirectory.url
    _ = try Self.folder(
      "siril-ABC", in: root, owner: ScratchOwner(owner: Self.dead, siril: Self.siril))
    let later = ProcessIdentity(pid: Self.siril.pid, startSeconds: 900, startMicroseconds: 0)
    let processes = FakeProcessTable(running: [later])

    _ = LeftoverSweep(
      roots: [.init(folder: root, prefix: "siril-")], table: processes.table, now: Self.now
    ).run()

    #expect(processes.terminatedPIDs.isEmpty)
    #expect(!Self.exists(root.appendingPathComponent("siril-ABC")), "that Siril is not ours")
  }
}
