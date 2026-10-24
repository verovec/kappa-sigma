import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import SwiftUI
import TestSupport
import Testing

/// The launch review of the retention policy (card 0114) over the recent projects: Ask lists and
/// deletes nothing until Delete all; Delete automatically removes and keeps the log for the
/// welcome window; a project open in a window, a snoozed review and kept stacks are left alone.
@Suite("RetentionReview — stacks never exported, reviewed at launch")
@MainActor
struct RetentionReviewTests {
  static let day: Int64 = 86_400_000

  /// A closed project with three stacks in `stacks/`: A (never exported), B (exported) and C
  /// (the newest); only A is a candidate once they are old.
  static func project() throws -> URL {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let package = try ProjectPackage.create(at: url)
    let store = package.store
    for name in ["A", "B", "C"] {
      let stack = try store.addStack(
        bundlePath: "stacks/\(name)", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
      let folder = url.appendingPathComponent("stacks/\(name)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(count: 4096).write(to: folder.appendingPathComponent("trim_RGB.fits"))
      if name == "B" {
        let image = try #require(try store.images(stackID: stack.id).first)
        try store.addExport(
          stackID: stack.id, imageID: image.id, headStepID: nil, folder: "/tmp/out",
          settingsJSON: "{}", files: ["final.png"])
      }
    }
    try package.close()
    return url
  }

  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.retention.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  static func review(
    _ url: URL, defaults: UserDefaults, mode: RetentionPolicy.Mode = .ask, daysLater: Int64 = 60,
    open: Set<String> = []
  ) -> RetentionReview {
    let setting = RetentionSetting(defaults: defaults)
    setting.policy = RetentionPolicy(mode: mode, days: 30)
    let now = Int64(Date().timeIntervalSince1970 * 1000) + daysLater * day
    return RetentionReview(
      setting: setting, recentURLs: { [url] }, openProjects: { open }, now: { now })
  }

  /// The keys of the projects open in a window, changed while a test runs.
  final class OpenProjects {
    var keys: Set<String> = []
  }

  @Test("a project opened between the scan and Delete all keeps its stacks", .scratchDirectory)
  func testOpenedSinceTheScanKept() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()
    let open = OpenProjects()
    let setting = RetentionSetting(defaults: defaults)
    let now = Int64(Date().timeIntervalSince1970 * 1000) + 60 * Self.day
    let review = RetentionReview(
      setting: setting, recentURLs: { [url] }, openProjects: { open.keys }, now: { now })
    await review.scan()
    #expect(review.pending.count == 1)
    open.keys = [WelcomeModel.key(url)]
    await review.deleteAll()
    #expect(review.pending.isEmpty && review.removed.isEmpty)
    #expect(try Self.names(url) == ["stacks/A", "stacks/B", "stacks/C"])

    await review.scan()
    open.keys = []
    await review.scan()
    open.keys = [WelcomeModel.key(url)]
    await review.keep()
    let again = RetentionReview(
      setting: setting, recentURLs: { [url] }, openProjects: { [] }, now: { now })
    await again.scan()
    #expect(again.pending.count == 1, "Keep never writes into a project a window has open")
  }

  @Test(
    "Delete all applies the policy again: a stack exported since the scan stays",
    .scratchDirectory)
  func testDeleteAllReappliesThePolicy() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()
    let setting = RetentionSetting(defaults: defaults)
    let now = Int64(Date().timeIntervalSince1970 * 1000) + 60 * Self.day
    let review = RetentionReview(
      setting: setting, recentURLs: { [url] }, openProjects: { [] }, now: { now })
    await review.scan()
    #expect(review.pending.map(\.stack.bundlePath) == ["stacks/A"])
    // Exported while the sheet waited: no longer a candidate.
    let package = try ProjectPackage.open(at: url)
    let stack = try #require(review.pending.first).stack
    let image = try #require(try package.store.images(stackID: stack.id).first)
    try package.store.addExport(
      stackID: stack.id, imageID: image.id, headStepID: nil, folder: "/tmp/out", settingsJSON: "{}",
      files: ["final.png"])
    try package.close()
    await review.deleteAll()
    #expect(review.removed.isEmpty)
    #expect(try Self.names(url) == ["stacks/A", "stacks/B", "stacks/C"])
  }

  static func names(_ url: URL) throws -> [String] {
    let package = try ProjectPackage.open(at: url)
    defer { try? package.close() }
    return try package.store.stacks().map(\.bundlePath)
  }

  @Test("Ask lists A and deletes nothing until Delete all", .scratchDirectory)
  func testAskModeDeletesNothing() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()
    let review = Self.review(url, defaults: defaults)
    await review.scan()
    #expect(review.pending.map(\.stack.bundlePath) == ["stacks/A"])
    #expect(review.pending.allSatisfy { $0.bytes > 0 } && review.removed.isEmpty)
    #expect(try Self.names(url) == ["stacks/A", "stacks/B", "stacks/C"])

    await review.deleteAll()
    #expect(review.pending.isEmpty)
    #expect(review.removed.map(\.stack.bundlePath) == ["stacks/A"], "the notice says what went")
    #expect(try Self.names(url) == ["stacks/B", "stacks/C"])
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("stacks/A").path))
  }

  @Test(
    "Delete automatically removes A and keeps the log for the welcome window", .scratchDirectory)
  func testAutoModeLogs() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()
    let review = Self.review(url, defaults: defaults, mode: .automatic)
    await review.scan()
    #expect(review.pending.isEmpty)
    #expect(review.removed.map(\.stack.bundlePath) == ["stacks/A"])
    #expect(try Self.names(url) == ["stacks/B", "stacks/C"])
    review.dismissRemoved()
    #expect(review.removed.isEmpty)
  }

  @Test(
    "young stacks, an open project, a snooze and kept stacks: nothing listed", .scratchDirectory)
  func testLeftAlone() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()

    let young = Self.review(url, defaults: defaults, daysLater: 10)
    await young.scan()
    #expect(young.pending.isEmpty)

    let open = Self.review(url, defaults: defaults, open: [WelcomeModel.key(url)])
    await open.scan()
    #expect(open.pending.isEmpty)

    let snoozed = Self.review(url, defaults: defaults)
    await snoozed.scan()
    snoozed.remindLater()
    #expect(snoozed.pending.isEmpty)
    let again = Self.review(url, defaults: defaults)
    await again.scan()
    #expect(again.pending.isEmpty, "reminded in 7 days, not before")

    let (otherDefaults, other) = try Self.suite()
    defer { otherDefaults.removePersistentDomain(forName: other) }
    let kept = Self.review(url, defaults: otherDefaults)
    await kept.scan()
    await kept.keep()
    let afterKeep = Self.review(url, defaults: otherDefaults)
    await afterKeep.scan()
    #expect(afterKeep.pending.isEmpty, "a kept stack is never asked about again")
    let moved = url.deletingLastPathComponent().appendingPathComponent("M31-2026.astrostack")
    try FileManager.default.moveItem(at: url, to: moved)
    let afterMove = Self.review(moved, defaults: otherDefaults)
    await afterMove.scan()
    #expect(afterMove.pending.isEmpty, "the decision lives in the project: a move keeps it")
    try FileManager.default.moveItem(at: moved, to: url)
    #expect(try Self.names(url) == ["stacks/A", "stacks/B", "stacks/C"])
  }

  @Test(
    "the launch sheet and the welcome notice lay out in each language", .scratchDirectory,
    arguments: ["en", "fr"])
  func testViewsLayOut(_ language: String) async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let url = try Self.project()
    let asking = Self.review(url, defaults: defaults)
    await asking.scan()
    let sheet = NSHostingView(
      rootView: RetentionSheet(review: asking).environment(\.locale, Locale(identifier: language)))
    sheet.layoutSubtreeIfNeeded()
    #expect(sheet.fittingSize.width >= 520)

    let removing = Self.review(url, defaults: defaults, mode: .automatic)
    await removing.scan()
    #expect(removing.removed.count == 1)
    let model = WelcomeModel(recentURLs: { [] }, tools: WelcomeViewTests.mixedTools)
    let welcome = NSHostingView(
      rootView: WelcomeView(
        model: model, actions: .init(open: { _ in }, choose: {}, create: { _ in url }),
        retention: removing
      ).environment(\.locale, Locale(identifier: language)))
    welcome.layoutSubtreeIfNeeded()
    #expect(welcome.fittingSize.height > 0)
  }
}
