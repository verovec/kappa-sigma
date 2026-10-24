import Foundation
import StackKit
import TestSupport
import Testing

/// `ScratchSpace` reads the room of the scratch folder's volume before the run creates it.
@Suite("ScratchSpace — free bytes of the scratch volume")
struct ScratchSpaceTests {
  @Test(
    "a folder the run has not created yet reads its existing ancestor's volume", .scratchDirectory)
  func testMissingFolderReadsAncestor() throws {
    let scratch = try ScratchDirectory.url
    let existing = try #require(ScratchSpace.available(at: scratch))
    let missing = try #require(
      ScratchSpace.available(at: scratch.appendingPathComponent("Work/run_1", isDirectory: true)))
    #expect(existing > 0)
    // The same volume, read twice: other processes write meanwhile, never a whole gigabyte here.
    #expect(abs(missing - existing) < 1_000_000_000)
  }

  @Test("a folder on a disk that is not mounted has no known room, never the startup disk's")
  func testUnmountedVolume() {
    let unplugged = URL(fileURLWithPath: "/Volumes/NotMounted-\(UUID().uuidString)/AstroStack/Work")
    #expect(ScratchSpace.available(at: unplugged) == nil)
  }
}
