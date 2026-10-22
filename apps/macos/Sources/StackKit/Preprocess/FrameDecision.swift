/// What the user decided on a lane's frames at the review breakpoint (card 0069): frames to leave
/// out and auto-rejected frames to stack anyway, by `FrameGrade.index`.
///
/// Empty means « as graded ». Recorded with the stack (`StackRecord`) and in `grades.json`, so a
/// run can be read back with the hand it was given.
package struct FrameDecision: Codable, Equatable, Sendable {
  /// 1-based sequence positions the user rejected.
  package var exclude: [Int]
  /// 1-based sequence positions the user kept despite the grader.
  package var forceKeep: [Int]

  /// A decision; both lists are kept sorted and without duplicates.
  package init(exclude: [Int] = [], forceKeep: [Int] = []) {
    self.exclude = Array(Set(exclude)).sorted()
    self.forceKeep = Array(Set(forceKeep)).sorted()
  }

  /// Nothing to change.
  package var isEmpty: Bool { exclude.isEmpty && forceKeep.isEmpty }

  private enum CodingKeys: String, CodingKey {
    case exclude
    case forceKeep = "force_keep"
  }

  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      exclude: try container.decodeIfPresent([Int].self, forKey: .exclude) ?? [],
      forceKeep: try container.decodeIfPresent([Int].self, forKey: .forceKeep) ?? [])
  }
}
