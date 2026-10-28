import Foundation
import TestSupport
import Testing

/// The `app-run` recipes (card 0147): a rebuilt app replaces the running one — a running
/// AstroStack is asked to quit (never killed) and waited for, then the bundle opens; `open -n`
/// (a second instance beside the old one, its own menus and recents) is gone.
@Suite("justfile — app-run never starts a second instance")
struct JustfileTests {
  static func text(_ relativePath: String) throws -> String {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    return try String(
      contentsOf: URL(fileURLWithPath: root + "/../../" + relativePath), encoding: .utf8)
  }

  @Test("testAppRun_noNewInstance: the recipes go through the run script, never `open -n`")
  func testAppRun_noNewInstance() throws {
    let justfile = try Self.text("justfile")
    #expect(!justfile.contains("open -W -n") && !justfile.contains("open -n"))
    for recipe in ["app-run-release", "app-run"] {
      let body = try #require(justfile.range(of: "\n\(recipe) *projects:"))
      let rest = justfile[body.upperBound...]
      #expect(rest.prefix(200).contains("scripts/app-run.sh"), "\(recipe) runs the script")
    }
    let script = try Self.text("scripts/app-run.sh")
    #expect(
      script.contains("to quit\" -e 'end ignoring'"), "asked, never waited for: the loop judges")
    #expect(script.contains("ignoring application responses"))
    #expect(
      script.contains("lsappinfo find"),
      "the running app by bundle id, no AppleScript, no path regex")
    #expect(
      script.contains("another AstroStack is running"),
      "never quits an AstroStack of another bundle")
    #expect(script.contains("exit 1"), "a quit that never happens fails, never opens the old build")
    #expect(script.contains("open -W -a") && !script.contains("open -W -n"))
    #expect(!script.contains("pkill") && !script.contains("kill -"), "asked to quit, never killed")
  }
}
