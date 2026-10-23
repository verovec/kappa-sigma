import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// A paused run's folder is its checkpoint (card 0097): never a leftover, never removed.
@MainActor
@Suite("Run leftovers — a paused run's folder is kept")
struct RunLeftoversPauseTests {
  @Test("a paused run's folder is not offered for deletion", .scratchDirectory)
  func testPausedFolderNotListed() async throws {
    let harness = try RunPauseTests.harness()
    defer { try? harness.fixture.project.close() }
    _ = try await RunPauseTests.pausedRun(harness)

    #expect(harness.fixture.window.leftoverStacks.isEmpty)
    let reopened = ProjectWindowModel(
      store: { harness.fixture.project.store }, folder: { harness.fixture.project.url })
    #expect(reopened.leftoverStacks.isEmpty, "listed at open neither")
  }

  @Test("a continued run that fails keeps its paused folder and row", .scratchDirectory)
  func testFailedContinueKeepsCheckpoint() async throws {
    let harness = try RunPauseTests.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    _ = try await RunPauseTests.pausedRun(harness)
    let paused = try #require(try fixture.project.store.pausedStacks().first)
    let output = fixture.project.url.appendingPathComponent(paused.bundlePath)
    // The checkpoint's master goes, so only the « resumed » guard keeps the folder.
    try FileManager.default.removeItem(at: output.appendingPathComponent("master_RGB.fits"))
    let failing = ProjectWindowModel(
      store: { fixture.project.store }, folder: { fixture.project.url },
      services: { _ in ImportServices(planning: { try await ImportPlanningStub.empty($0) }) },
      runs: RunServices(
        run: RunLeftoversTests.failingRun(writing: [], error: RunLeftoversTests.Failure.siril),
        now: { ProjectTests.start }, scratch: fixture.work, timeZone: .gmt))

    failing.continueRun(paused.id)
    await failing.run?.settled()

    #expect(FileManager.default.fileExists(atPath: output.path))
    #expect(try fixture.project.store.pausedStacks().map(\.id) == [paused.id])
  }
}
