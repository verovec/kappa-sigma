/// What the combined view says after a branch edit (card 0119): the main steps that will run
/// again and the branches whose head moved under them.
package struct StaleNotice: Equatable, Sendable {
  /// The main steps from the first stale one on, 0-based.
  package let steps: [Int]
  /// The branches that changed, by layer id.
  package let branches: [String]

  /// The steps `steps` outdated by `branches`.
  package init(steps: [Int], branches: [String]) {
    self.steps = steps
    self.branches = branches
  }
}
