/// How far a project has come, as counts: what the journey sidebar derives its stage states from
/// (card 0076).
package struct ProjectSummary: Equatable, Sendable {
  /// Capture nights and legacy runs recorded.
  package var sources = 0
  /// Stacks (bundles) recorded.
  package var stacks = 0
  /// Images of every stack.
  package var images = 0
  /// History steps applied to those images.
  package var historySteps = 0

  /// A summary of these counts.
  package init(sources: Int = 0, stacks: Int = 0, images: Int = 0, historySteps: Int = 0) {
    self.sources = sources
    self.stacks = stacks
    self.images = images
    self.historySteps = historySteps
  }
}
