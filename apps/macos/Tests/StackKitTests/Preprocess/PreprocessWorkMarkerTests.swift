import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

@Suite("Preprocessor — the run's work folder names its owner")
struct PreprocessWorkMarkerTests {
  @Test(
    "Siril works in a folder marked by the process running it, so a killed app's is swept",
    .scratchDirectory)
  func testWorkFolderMarked() async throws {
    let request = try PreprocessorTests.request()
    let seen = Mutex<ScratchOwner?>(nil)
    let siril = PipelineSiril(onRun: { _ in
      seen.withLock { $0 = $0 ?? ScratchOwner.read(request.work) }
    })
    let (_, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(siril)).run(request))
    #expect(error == nil)
    let marker = try #require(seen.withLock { $0 })
    #expect(marker.owner.pid == getpid())
  }
}
