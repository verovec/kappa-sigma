import AstroStackApp
import Foundation
import StackKit
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
}
