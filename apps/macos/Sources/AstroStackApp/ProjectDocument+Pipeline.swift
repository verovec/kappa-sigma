package import AppKit

// MARK: - The Studio's pipeline commands (card 0088)

extension ProjectDocument {
  /// Edit › Run Pipeline (⌥⌘R): the pipeline runs from where the history stands to its next
  /// breakpoint.
  @objc package func runPipeline(_ sender: Any?) {
    guard let pipeline = windowModel?.workspace?.pipeline else { return }
    Task { await pipeline.run() }
  }

  /// Edit › Continue Pipeline (⌥⌘↩): the breakpoint's step with the panel's values, then on.
  @objc package func continuePipeline(_ sender: Any?) {
    guard let pipeline = windowModel?.workspace?.pipeline else { return }
    Task { await pipeline.continueRun() }
  }

  /// Edit › Replay Pipeline…: the stack chooser.
  @objc package func replayPipeline(_ sender: Any?) {
    windowModel?.isChoosingReplay = true
  }

  /// The pipeline commands' actions.
  package static let pipelineActions: [Selector] = [
    #selector(runPipeline(_:)), #selector(continuePipeline(_:)), #selector(replayPipeline(_:)),
  ]

  /// Whether pipeline command `action` is enabled: on the Studio stage with a pipeline not
  /// running; Continue at a breakpoint whose process the panel shows; Replay with another stack
  /// to replay on.
  package static func pipelineEnabled(_ action: Selector, in window: ProjectWindowModel?) -> Bool {
    guard let window, window.selection == .studio, let pipeline = window.workspace?.pipeline,
      !pipeline.isRunning
    else { return false }
    switch action {
    case #selector(continuePipeline(_:)): return pipeline.canContinue
    case #selector(replayPipeline(_:)): return !window.replayTargets.isEmpty
    default: return true
    }
  }
}
