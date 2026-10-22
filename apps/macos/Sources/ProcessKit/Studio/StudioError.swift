/// Why the Studio could not do what was asked.
package enum StudioError: Error, Equatable, Sendable {
  /// No registered process has this id.
  case unknownProcess(String)
  /// The stack has no layer to start the working image from.
  case emptyBundle
  /// A host-tool process (`ImageProcess.hostTool`) recorded without its tool: the step would
  /// claim what the tool never did.
  case needsTool(String)
}
