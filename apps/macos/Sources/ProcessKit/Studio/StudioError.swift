/// Why the Studio could not do what was asked.
package enum StudioError: Error, Equatable, Sendable {
  /// No registered process has this id.
  case unknownProcess(String)
  /// The stack has no layer to start the working image from.
  case emptyBundle
  /// A batch process runs in its host tool, never on the GPU: its preview is its result.
  case runsInTool(String)
  /// The history's head moved while the batch process ran: its result is not recorded.
  case headMoved(String)
  /// A batch process is running: the history waits for it (undo, redo, another Apply).
  case toolRunning
}
