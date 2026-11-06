import AstroStackApp
import Foundation
import ProjectKit

extension ProjectTests {
  /// Writes one readable stack (`stacks/A`) into `fixture`'s project and shows the Studio on it;
  /// the workspace loads once `openStudio()` runs, from the test or the window's own task.
  static func addStudioStack(_ fixture: Fixture) throws {
    let output = fixture.project.url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try writeBundle(in: output, runID: "A")
    _ = try fixture.project.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    fixture.window.refresh()
    fixture.window.select(.studio)
  }
}
