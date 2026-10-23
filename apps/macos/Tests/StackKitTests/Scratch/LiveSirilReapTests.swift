import Foundation
import StackKit
import TestSupport
import Testing

/// A real `siril-cli -p` whose owner is gone is stopped by the sweep, and its FIFO folder goes.
@Suite(
  "Live Siril reap", .liveFixtures,
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .tags(.live), .serialized,
  .timeLimit(.minutes(2)))
struct LiveSirilReapTests {
  static let app = FileManager.default.temporaryDirectory
    .appendingPathComponent("AstroStack", isDirectory: true)

  @Test("an orphan Siril is stopped and its FIFO folder removed", .scratchDirectory)
  func testOrphanSirilReaped() async throws {
    let session = SirilSession(
      binary: try SirilTool.locate(), workDirectory: try ScratchDirectory.url)
    try await session.start()
    let folder = try #require(await session.fifoFolder)
    #expect(folder.deletingLastPathComponent().standardizedFileURL == Self.app.standardizedFileURL)
    var marker = try #require(ScratchOwner.read(folder), "the session's FIFO folder is marked")
    #expect(marker.owner.pid == getpid())
    let siril = try #require(marker.siril, "the Siril pid is recorded once it launched")
    #expect(ProcessTable.live.executable(siril.pid)?.hasSuffix("/siril-cli") == true)

    // The owner dies: the same pid now names a process started at another time (a SIGKILLed
    // app whose pid the kernel gave away), which is all the sweep can see of a dead owner.
    marker.owner.startSeconds += 1
    try marker.write(to: folder)
    let removed = LeftoverSweep(roots: [.init(folder: Self.app, prefix: "siril-")]).run()

    #expect(removed.map(\.path.lastPathComponent).contains(folder.lastPathComponent))
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(ProcessTable.live.identity(siril.pid) != siril, "no siril-cli left with that folder")
    await session.stop()
  }
}
