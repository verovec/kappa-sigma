import StackKit
import TestSupport
import Testing

/// The live client against the Mac's real install (skips without Siril).
@Suite(
  "Live host tools", .liveFixtures,
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .tags(.live),
  .timeLimit(.minutes(2)))
struct LiveHostToolsTests {
  @Test("the installed Siril is found with a version at the floor or above")
  func testFindsInstalledSiril() async throws {
    // A generous timeout: the live suites run beside other Siril sessions on a loaded machine.
    let status = await HostTools.live(timeout: .seconds(60)).locate(.siril)

    guard case .found(let path, let version) = status else {
      Issue.record("Siril not usable: \(status)")
      return
    }
    #expect(path == (try SirilTool.locate()))
    #expect(version?.hasPrefix("1.") == true)
  }
}
