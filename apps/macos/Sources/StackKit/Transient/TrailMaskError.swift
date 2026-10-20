/// Why the mask could not run.
package enum TrailMaskError: Error, Equatable, Sendable {
  /// Frame `index` does not have the first frame's planes and size (registered frames must).
  case mismatchedFrame(index: Int)
}
