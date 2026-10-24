internal import Foundation
internal import OSLog

/// Which stacks are offered for deletion, and what happens to them (card 0114, app Settings ›
/// Storage).
///
/// A candidate is a finished stack never exported, unused for more than `days` (its last open in
/// the Studio, else its creation), neither its project's newest nor one it protects (chosen for
/// its Studio, kept by the user). Exported stacks are never
/// candidates: an export may need a re-export. Pure over its inputs: the caller reads the rows,
/// measures the folders and deletes.
package struct RetentionPolicy: Equatable, Sendable {
  /// What the launch does with the candidates.
  package enum Mode: String, CaseIterable, Sendable {
    /// The default: a sheet lists them; nothing goes until the user says so (R2).
    case ask
    /// Each one is deleted and logged, the list shown once in the welcome window.
    case automatic
  }

  /// The default age, in days.
  package static let defaultDays = 30
  private static let dayMs: Int64 = 86_400_000

  package var mode: Mode
  /// Days without use before a stack never exported is a candidate.
  package var days: Int

  /// A policy.
  package init(mode: Mode = .ask, days: Int = Self.defaultDays) {
    self.mode = mode
    self.days = days
  }

  /// The candidates among one project's `stacks`, oldest first; `exportCounts` by stack id;
  /// `protected` are kept like the newest (the Studio's chosen stack, the ones the user kept).
  package func candidates(
    _ stacks: [ProjectStack], exportCounts: [Int64: Int], protected: Set<Int64> = [], now: Int64
  ) -> [ProjectStack] {
    let done = stacks.filter { $0.status == .done }
    let kept = protected.union(done.map(\.id).max().map { [$0] } ?? [])
    return done.filter { stack in
      !kept.contains(stack.id) && (exportCounts[stack.id] ?? 0) == 0
        && now - (stack.openedAt ?? stack.createdAt) > Int64(days) * Self.dayMs
    }
    .sorted { $0.id < $1.id }
  }

  /// Deletes each candidate (the user confirmed, or the policy is automatic) and logs it.
  ///
  /// Returns the ones deleted. A failure is logged and left out: its stack stays listed next time.
  @discardableResult
  package static func delete(
    _ candidates: [RetentionCandidate], delete: (RetentionCandidate) throws -> Void
  ) -> [RetentionCandidate] {
    candidates.filter { candidate in
      let name = "\(candidate.project.lastPathComponent)/\(candidate.stack.bundlePath)"
      do {
        try delete(candidate)
        let bytes = candidate.bytes
        ProjectStore.storageLogger.notice(
          "retention deleted \(name, privacy: .public) (\(bytes) bytes)")
        return true
      } catch {
        ProjectStore.storageLogger.error(
          "retention could not delete \(name, privacy: .public): \(error)")
        return false
      }
    }
  }
}
