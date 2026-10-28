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
  /// What retention removed at this launch (automatically or by Delete All).
  package private(set) var removed: [RetentionCandidate] = []
  /// What retention removed and the welcome window has not shown yet, across launches.
  package private(set) var unseen: [String] = []
  /// The bytes of `unseen`.
  package private(set) var unseenBytes: Int64 = 0

  private let setting: RetentionSetting
  private let recentURLs: @MainActor () -> [URL]
  private let openProjects: @MainActor () -> Set<String>
  private let now: @Sendable () -> Int64
  /// Bumped by `postpone`: a scan that started before writes no sheet.
  @ObservationIgnored private var postponements = 0
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
    unseen = setting.unseen
    unseenBytes = setting.unseenBytes
  }

  /// Lists the candidates of every closed recent project, off the main actor, then applies the
  /// policy: Ask fills `pending`, Delete automatically fills `removed`.
  package func scan() async {
    let policy = setting.policy
    let stamp = now()
    guard policy.mode == .automatic || setting.snoozedUntil <= stamp else { return }
    let open = openProjects()
    let urls = recentURLs().filter { !open.contains(WelcomeModel.key($0)) }
    let postponed = postponements
    let found = await Self.candidates(urls, policy: policy, now: stamp)
    switch policy.mode {
    case .ask:
      // The welcome window closed while the folders were measured: asked again next launch.
      guard postponed == postponements else { return }
      pending = found
    case .automatic: record(await deleteEach(found))
    }
  }

  /// Delete all: every pending stack goes, the welcome window says which; one that fails or
  /// whose project opened meanwhile stays, listed at the next launch.
  package func deleteAll() async {
    let candidates = pending
    pending = []
    record(await deleteEach(candidates))
  }

  /// Deletes `candidates` project by project off the main actor; the ones deleted, in order.
  ///
  /// Each project is checked closed right before it is touched: one opened since the scan (a
  /// restored document, a double click) is left to its own Storage section, whose Studio may
  /// show it. The policy is applied again to the project as it is then: a stack opened, chosen,
  /// kept or exported since the scan stays.
  @discardableResult
  private func deleteEach(_ candidates: [RetentionCandidate]) async -> [RetentionCandidate] {
    let policy = setting.policy
    var deleted: [RetentionCandidate] = []
    for (project, group) in Self.byProject(candidates) where !isOpen(project) {
      deleted += await Self.deleteOffMain(group, in: project, policy: policy, now: now())
    }
    return deleted
  }

  /// A project open in a window now.
  private func isOpen(_ project: URL) -> Bool {
    openProjects().contains(WelcomeModel.key(project))
  }

  /// `candidates` grouped by project, in the order the projects first appear.
  private nonisolated static func byProject(_ candidates: [RetentionCandidate])
    -> [(URL, [RetentionCandidate])]
  {
    var order: [URL] = []
    var groups: [URL: [RetentionCandidate]] = [:]
    for candidate in candidates {
      if groups[candidate.project] == nil { order.append(candidate.project) }
      groups[candidate.project, default: []].append(candidate)
    }
    return order.map { ($0, groups[$0] ?? []) }
  }

  /// Closes the sheet without a decision (Escape): asked again at the next launch.
  package func postpone() {
    postponements += 1
    pending = []
  }

  /// Keep: these stacks are never offered again, recorded in their own projects; a project
  /// opened meanwhile is not written (its window owns it): asked about again next launch.
  package func keep() async {
    let candidates = pending
    pending = []
    for (project, group) in Self.byProject(candidates) where !isOpen(project) {
      await Self.keepOffMain(Set(group.map(\.stack.id)), in: project)
    }
  }

  /// Remind in 7 days: the sheet comes back at the first launch after that.
  package func remindLater() {
    setting.snoozedUntil = now() + Self.snooze
    pending = []
  }

  /// Keeps what went for the welcome window, persisted until its OK: a project window that
  /// closes the welcome window first never hides it (R2).
  private func record(_ deleted: [RetentionCandidate]) {
    removed = deleted
    guard !deleted.isEmpty else { return }
    unseen += deleted.map(\.label)
    unseenBytes += deleted.reduce(0) { $0 + $1.bytes }
    setting.unseen = unseen
    setting.unseenBytes = unseenBytes
  }

  /// The welcome window showed what was removed.
  package func dismissRemoved() {
    removed = []
    unseen = []
    unseenBytes = 0
    setting.unseen = []
    setting.unseenBytes = 0
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
      return policy.candidates(in: usage, now: now).compactMap { stack in
        guard !Task.isCancelled else { return nil }
        return RetentionCandidate(
          project: url, stack: stack,
          bytes: LeftoverSweep.allocatedBytes(url.appendingPathComponent(stack.bundlePath)))
      }
    }
  }

  /// Deletes the candidates of one project that are still candidates now, opening it once.
  ///
  /// Returns the ones deleted (logged). The package is closed without removing its WAL files: a window may be
  /// opening it at this moment.
  @concurrent
  private nonisolated static func deleteOffMain(
    _ candidates: [RetentionCandidate], in project: URL, policy: RetentionPolicy, now: Int64
  ) async -> [RetentionCandidate] {
    guard
      let usage = try? ProjectPackage.readUsage(
        at: project, chosenKey: ProjectWindowModel.stackSettingKey)
    else { return [] }
    let still = Set(policy.candidates(in: usage, now: now).map(\.id))
    let current = candidates.filter { still.contains($0.stack.id) }
    guard !current.isEmpty else { return [] }
    let package: ProjectPackage
    do {
      package = try ProjectPackage.open(at: project, owning: false)
    } catch {
      logger.error("could not open \(project.path) to delete stacks: \(error)")
      return []
    }
    defer { try? package.closeKeepingWAL() }
    // A stack whose rows went but whose folder stayed (a 0113 leftover now) is reported deleted,
    // with nothing freed; one already gone (another window deleted it) is not reported.
    var stayed: Set<Int64> = []
    let deleted = RetentionPolicy.delete(current) {
      let id = $0.stack.id
      guard try package.store.stack(id: id) != nil else { throw AlreadyGone() }
      if try !package.store.deleteStack(id: id, packageFolder: project, openStackID: nil) {
        stayed.insert(id)
      }
    }
    return deleted.map {
      stayed.contains($0.stack.id)
        ? RetentionCandidate(project: $0.project, stack: $0.stack, bytes: 0) : $0
    }
  }

  /// Records stacks `ids` as kept in `project`, closed without removing its WAL files; a project
  /// that cannot be written is logged and asked about again.
  @concurrent
  private nonisolated static func keepOffMain(_ ids: Set<Int64>, in project: URL) async {
    do {
      let package = try ProjectPackage.open(at: project, owning: false)
      defer { try? package.closeKeepingWAL() }
      try package.store.keepStacks(ids)
    } catch {
      logger.error("could not keep stacks of \(project.path): \(error)")
    }
  }

  private struct AlreadyGone: Error {}

  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "App/retention")
}
