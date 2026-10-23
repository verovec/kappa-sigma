/// Why the store refused a write, with what the user can fix.
package enum ProjectStoreError: Error, Equatable, Sendable {
  /// A saved item (a pipeline) needs a name.
  case emptyName
  /// A JSON body that is not UTF-8 text.
  case notText
  /// The step is not one of the image's (card 0087: an image's head is its own step).
  case notImageStep(imageID: Int64, stepID: Int64)
  /// The stack is not a paused run (card 0097): only a paused run is completed or discarded.
  case notPaused(stackID: Int64)
}
