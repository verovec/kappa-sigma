import Foundation
import ProjectKit
import Testing

/// The retention policy (card 0114): which stacks are offered for deletion, and what Ask and
/// Delete automatically do with them. Exported stacks and a project's newest are never offered.
@Suite("RetentionPolicy — stacks never exported, unused for N days")
struct RetentionPolicyTests {
  static let day: Int64 = 86_400_000
  static let now: Int64 = 1_000 * day

  struct Case: Sendable, CustomTestStringConvertible {
    var name: String
    var ageDays: Int64
    var openedDaysAgo: Int64?
    var writtenDaysAgo: Int64?
    var exports: Int
    var status: ProjectStack.Status = .done
    var candidate: Bool
    var testDescription: String { name }
  }

  /// Every row is the older of two stacks; the newer one (id 99) is the project's newest.
  static let cases = [
    Case(name: "never exported, older than N", ageDays: 40, exports: 0, candidate: true),
    Case(name: "exported once, older than N", ageDays: 40, exports: 1, candidate: false),
    Case(name: "never exported, younger than N", ageDays: 10, exports: 0, candidate: false),
    Case(name: "exactly N days old", ageDays: 30, exports: 0, candidate: false),
    Case(
      name: "old but opened 2 days ago", ageDays: 90, openedDaysAgo: 2, exports: 0,
      candidate: false),
    Case(
      name: "old, last opened 31 days ago", ageDays: 90, openedDaysAgo: 31, exports: 0,
      candidate: true),
    Case(name: "a paused run", ageDays: 90, exports: 0, status: .paused, candidate: false),
    Case(
      name: "old, continued and finished 2 days ago", ageDays: 90, writtenDaysAgo: 2, exports: 0,
      candidate: false),
  ]

  static func stack(
    id: Int64, ageDays: Int64, openedDaysAgo: Int64? = nil, writtenDaysAgo: Int64? = nil,
    status: ProjectStack.Status = .done
  ) -> ProjectStack {
    ProjectStack(
      id: id, bundlePath: "stacks/\(id)", sourceIDs: [], paramsJSON: "{}", status: status,
      openedAt: openedDaysAgo.map { now - $0 * day }, createdAt: now - ageDays * day,
      updatedAt: now - (writtenDaysAgo ?? ageDays) * day)
  }

  static let policy = RetentionPolicy(mode: .ask, days: 30)

  @Test("only never exported, unused for more than N days, not the newest", arguments: cases)
  func testCandidates(_ row: Case) {
    let older = Self.stack(
      id: 1, ageDays: row.ageDays, openedDaysAgo: row.openedDaysAgo,
      writtenDaysAgo: row.writtenDaysAgo, status: row.status)
    let newest = Self.stack(id: 99, ageDays: 400)
    let found = Self.policy.candidates(
      [older, newest], exportCounts: row.exports > 0 ? [1: row.exports] : [:], now: Self.now)
    #expect(found.map(\.id) == (row.candidate ? [1] : []))
  }

  @Test("the newest finished stack is never a candidate, even alone and old")
  func testNewestKept() {
    let only = Self.stack(id: 7, ageDays: 400)
    let paused = Self.stack(id: 8, ageDays: 400, status: .paused)
    #expect(Self.policy.candidates([only, paused], exportCounts: [:], now: Self.now).isEmpty)
  }

  static func candidates() -> [RetentionCandidate] {
    [1, 2].map {
      RetentionCandidate(
        project: URL(fileURLWithPath: "/p/M31.astrostack"), stack: Self.stack(id: $0, ageDays: 90),
        bytes: $0 * 1_000_000_000)
    }
  }

  @Test("a protected stack (chosen for the Studio, kept by the user) is kept like the newest")
  func testProtectedKept() {
    let stacks = [1, 2, 3, 4].map { Self.stack(id: $0, ageDays: 90) }
    let found = Self.policy.candidates(stacks, exportCounts: [:], protected: [1, 3], now: Self.now)
    #expect(found.map(\.id) == [2])
  }

  struct Refused: Error {}

  @Test("delete removes each candidate and returns the ones deleted; a failure is left out")
  func testDeleteLogsAndSkipsFailures() {
    var deleted: [Int64] = []
    let removed = RetentionPolicy.delete(Self.candidates()) {
      if $0.stack.id == 2 { throw Refused() }
      deleted.append($0.stack.id)
    }
    #expect(deleted == [1])
    #expect(removed == Array(Self.candidates().prefix(1)))
  }
}
