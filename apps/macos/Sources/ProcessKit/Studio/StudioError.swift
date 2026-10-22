/// Why the Studio could not do what was asked.
package enum StudioError: Error, Equatable, Sendable {
  /// No registered process has this id.
  case unknownProcess(String)
  /// The stack has no layer to start the working image from.
  case emptyBundle
  /// The step's output has another size than the head (a crop or a quarter turn came after it):
  /// it cannot be compared pixel for pixel.
  case otherSize(step: Int)
}
