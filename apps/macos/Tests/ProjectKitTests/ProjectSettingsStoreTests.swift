import Foundation
import ProjectKit
import TestSupport
import Testing

/// `project_settings` (migration 0003, card 0076): small per-project values the windows restore,
/// and the counts the journey sidebar derives its states from.
@Suite("ProjectStore: per-project settings and the journey summary")
struct ProjectSettingsStoreTests {
  @Test("a setting is absent, then written, overwritten and kept across reopen", .scratchDirectory)
  func testSettingRoundTrip() throws {
    let package = try ProjectStoreTests.newPackage()
    #expect(try package.store.setting("workspace.stage") == nil)
    try package.store.setSetting("workspace.stage", to: "review")
    try package.store.setSetting("workspace.stage", to: "studio")
    #expect(try package.store.setting("workspace.stage") == "studio")
    try package.close()

    let reopened = try ProjectPackage.open(at: package.url)
    defer { try? reopened.close() }
    #expect(try reopened.store.setting("workspace.stage") == "studio")
  }

  @Test("an overwrite keeps the row and created_at, and moves updated_at", .scratchDirectory)
  func testSettingTimestamps() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let before = Int64(Date().timeIntervalSince1970 * 1000)
    try package.store.setSetting("k", to: "a")
    let first = try #require(package.store.settings().first)
    try package.store.setSetting("k", to: "b")
    let second = try package.store.settings()
    #expect(second.count == 1)
    #expect(second.first?.id == first.id && second.first?.value == "b")
    #expect(second.first?.createdAtMs == first.createdAtMs)
    #expect(first.createdAtMs >= before && (second.first?.updatedAtMs ?? 0) >= first.updatedAtMs)
  }

  @Test("the summary counts sources, stacks, images and history steps", .scratchDirectory)
  func testSummary() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    #expect(try store.summary() == ProjectSummary())

    let night = try store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    try store.addSource(kind: .night, path: "/captures/M31/2026-10-19")
    let stack = try store.addStack(bundlePath: "stacks/1", sourceIDs: [night.id], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "combine_RGB")
    try store.appendHistoryStep(
      imageID: image.id, processID: "stretch", paramsJSON: "{}", output: nil,
      contentHash: nil)
    #expect(
      try store.summary()
        == ProjectSummary(sources: 2, stacks: 1, images: 1, historySteps: 1))
  }
}
