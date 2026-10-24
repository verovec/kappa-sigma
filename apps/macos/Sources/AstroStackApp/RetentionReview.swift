package import Foundation
internal import OSLog
internal import Observation
package import ProjectKit
internal import StackKit

/// The retention policy at launch (card 0114), over the recent projects no window has open.
///
/// Ask (the default) lists the candidates for the launch sheet and deletes nothing until Delete
/// all; Delete automatically removes them and keeps the list for the welcome window to show once.
/// A project open in a window is left to its own Storage section: its Studio may show a stack.
@Observable
package final class RetentionReview {
  /// What the sheet asks about, by project then stack.
  package private(set) var pending: [RetentionCandidate] = []
  /// What the automatic policy removed at this launch, until the welcome window's OK.
  package private(set) var removed: [RetentionCandidate] = []

  private let setting: RetentionSetting
  private let recentURLs: @MainActor () -> [URL]
  private let openProjects: @MainActor () -> Set<String>
  private let now: @Sendable () -> Int64
  private static let snooze: Int64 = 7 * 86_400_000

  /// A review of `recentURLs` under `setting`; `openProjects` are the keys (`WelcomeModel.key`)
  /// of the projects open in a window; `now` is the clock in Unix ms.
  package init(
    setting: RetentionSetting, recentURLs: @escaping @MainActor () -> [URL],
    openProjects: @escaping @MainActor () -> Set<String>,
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.setting = setting
    self.recentURLs = recentURLs
    self.openProjects = openProjects
    self.now = now
  }

  /// Lists the candidates of every closed recent project, off the main actor, then applies the
  /// policy: Ask fills `pending`, Delete automatically fills `removed`.
  package func scan() async {
    let policy = setting.policy
    let stamp = now()
    guard policy.mode == .automatic || setting.snoozedUntil <= stamp else { return }
    let open = openProjects()
    let urls = recentURLs().filter { !open.contains(WelcomeModel.key($0)) }
    let found = await Self.candidates(urls, policy: policy, now: stamp)
    switch policy.mode {
    case .ask: pending = found
    case .automatic: removed = await deleteEach(found)
    }
  }

  /// Delete all: every pending stack goes, the welcome window says which; one that fails or
  /// whose project opened meanwhile stays, listed at the next launch.
  package func deleteAll() async {
    let candidates = pending
    pending = []
    removed = await deleteEach(candidates)
  }

  /// Deletes `candidates` one at a time off the main actor, the ones deleted in order.
  ///
  /// Each project is checked closed right before its stack goes: one opened since the scan (a
  /// restored document, a double click) is left to its own Storage section, whose Studio may
  /// show it.
  @discardableResult
  private func deleteEach(_ candidates: [RetentionCandidate]) async -> [RetentionCandidate] {
    var deleted: [RetentionCandidate] = []
    for candidate in candidates
    where !openProjects().contains(WelcomeModel.key(candidate.project)) {
      deleted += await Self.deleteOffMain(candidate)
    }
    return deleted
  }

  /// Closes the sheet without a decision (Escape): asked again at the next launch.
  package func postpone() {
    pending = []
  }

  /// Keep: these stacks are never offered again, recorded in their own projects.
  package func keep() async {
    let candidates = pending
    pending = []
    await Self.keepOffMain(candidates)
  }

  /// Remind in 7 days: the sheet comes back at the first launch after that.
  package func remindLater() {
    setting.snoozedUntil = now() + Self.snooze
    pending = []
  }

  /// The welcome window showed what was removed.
  package func dismissRemoved() {
    removed = []
  }

  @concurrent
  private nonisolated static func candidates(
    _ urls: [URL], policy: RetentionPolicy, now: Int64
  ) async -> [RetentionCandidate] {
    urls.flatMap { url -> [RetentionCandidate] in
      // Read-only: the scan never migrates nor checkpoints a project. One that cannot be read
      // (moved, foreign) or predates 0008 offers nothing.
      guard
        let usage = try? ProjectPackage.readUsage(
          at: url, chosenKey: ProjectWindowModel.stackSettingKey)
      else { return [] }
      return policy.candidates(
        usage.stacks, exportCounts: usage.exportCounts, protected: usage.protected, now: now
      ).map { stack in
        RetentionCandidate(
          project: url, stack: stack,
          bytes: LeftoverSweep.allocatedBytes(url.appendingPathComponent(stack.bundlePath)))
      }
    }
  }

  /// One candidate deleted off the main actor (folders of many GB), logged; empty on failure.
  @concurrent
  private nonisolated static func deleteOffMain(_ candidate: RetentionCandidate) async
    -> [RetentionCandidate]
  {
    RetentionPolicy.delete([candidate], delete: delete)
  }

  /// Records `candidates` as kept in their projects, each opened for the time of the write; a
  /// project that cannot be written is logged and asked about again.
  @concurrent
  private nonisolated static func keepOffMain(_ candidates: [RetentionCandidate]) async {
    for (project, kept) in Dictionary(grouping: candidates, by: \.project) {
      do {
        let package = try ProjectPackage.open(at: project)
        defer { try? package.close() }
        try package.store.keepStacks(Set(kept.map(\.stack.id)))
      } catch {
        logger.error("could not keep stacks of \(project.path): \(error)")
      }
    }
  }

  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "App/retention")

  /// Deletes one candidate in its project, opened for the time of the delete.
  private nonisolated static func delete(_ candidate: RetentionCandidate) throws {
    let package = try ProjectPackage.open(at: candidate.project)
    defer { try? package.close() }
    try package.store.deleteStack(
      id: candidate.stack.id, packageFolder: candidate.project, openStackID: nil)
  }
}
