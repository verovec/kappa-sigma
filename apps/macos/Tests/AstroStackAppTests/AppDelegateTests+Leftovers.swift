import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

@Suite("AppDelegate — the launch sweep's roots")
struct AppDelegateLeftoverRootsTests {
  static let defaultWork = URL(fileURLWithPath: "/private/tmp/T/AstroStack/Work", isDirectory: true)

  @Test(
    "the chosen work folder is swept, and the default one too once another was chosen",
    arguments: [
      ("/private/tmp/T/AstroStack/Work", ["/private/tmp/T/AstroStack/Work"]),
      (
        "/Volumes/Scratch/AstroStack/Work",
        ["/Volumes/Scratch/AstroStack/Work", "/private/tmp/T/AstroStack/Work"]
      ),
    ])
  func testWorkRoots(_ chosen: String, swept: [String]) {
    let roots = AppDelegate.leftoverRoots(
      work: URL(fileURLWithPath: chosen, isDirectory: true), defaultWork: Self.defaultWork)
    #expect(roots.filter { $0.prefix == "run_" }.map(\.folder.path) == swept)
    #expect(roots.contains { $0.prefix == "siril-" }, "Siril's FIFO folders, wherever runs go")
  }

  // Only a scratch root: the launch sweep is never run on the app's real folders by a test.
  @Test("the launch sweep removes a dead owner's run folder from its roots", .scratchDirectory)
  func testSweepAtLaunch() async throws {
    let work = try ScratchDirectory.url.appendingPathComponent("Work", isDirectory: true)
    let run = work.appendingPathComponent("run_20261024_030000", isDirectory: true)
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    try ScratchOwner(owner: ProcessIdentity(pid: 0, startSeconds: 1, startMicroseconds: 0))
      .write(to: run)

    await AppDelegate.sweepLeftovers(roots: [LeftoverSweep.Root(folder: work, prefix: "run_")])

    #expect(!FileManager.default.fileExists(atPath: run.path))
  }
}
