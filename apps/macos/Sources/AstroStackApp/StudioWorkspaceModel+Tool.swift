package import Foundation
internal import ImageKit
internal import ProcessKit
internal import StackKit

/// Apply for a host-tool process (card 0093): the tool runs in the background on the head, its
/// step is recorded only on the head it started from.
extension StudioWorkspaceModel {
  /// Runs the panel's host tool on the head in the background (card 0093).
  ///
  /// `done` runs once it ended, with whether its step was recorded. One run at a time: while
  /// one runs, nothing starts and `done(false)` runs at once.
  package func startTool(then done: @escaping (Bool) -> Void = { _ in }) {
    guard toolTask == nil else {
      failure = .app("A tool is already running: wait for it, or stop it.")
      return done(false)
    }
    toolTask = Task { [weak self] in
      let recorded = await self?.runTool() ?? false
      self?.toolTask = nil
      done(recorded)
    }
  }

  /// Stops the running host tool: nothing is recorded.
  package func cancelTool() {
    toolTask?.cancel()
  }

  /// Why no tool may run now, whatever the panel: a mask, or a pipeline run moving the head.
  package var toolRefusal: LocalizedStringResource? {
    // A host tool works on the whole image: under a mask, what is applied would not be what the
    // mask shows (R2). The side column shows the mask and its Clear under the panel (card 0111).
    if mask != nil {
      return .app("A host tool works on the whole image: clear the mask first (Mask row below).")
    }
    // A pipeline run moves the head too: the tool would record on another image.
    if pipeline?.isRunning == true {
      return .app("A pipeline run is going on: wait for it, then apply.")
    }
    return nil
  }

  /// The tool's run: its step recorded on the head it started from, never on another; whether
  /// it was.
  @discardableResult
  package func runTool() async -> Bool {
    guard let panel else { return false }
    guard let tool = tools[panel.type.id], toolRefusal == nil else {
      failure = toolRefusal ?? UserFacingError(StudioError.needsTool(panel.type.id)).message
      return false
    }
    var recorded = false
    toolRunNumber += 1
    let number = toolRunNumber
    let (id, params, head) = (panel.type.id, panel.params, studio.steps.last?.file)
    toolRun = ToolProgress(line: "", percent: nil)
    defer { toolRun = nil }
    // Refused before the tool runs (an engine's tool missing, card 0092): nothing else runs.
    // A mask or a pipeline run started while the probe ran is refused too.
    if let reason = await preflight(id, params: params) ?? toolRefusal {
      failure = reason
      return false
    }
    do {
      try Task.checkCancellation()
      // The head and the layers as the steps so far left them, copied for the tool to keep.
      let source = try PipelineRunner.BatchInput(
        history: studio.session.history, bundle: studio.session.bundle)
      var layers: [String: AstroImage] = [:]
      for (id, layer) in source.layers { layers[id] = Self.detached(layer) }
      let input = PipelineRunner.BatchInput(image: Self.detached(source.image), layers: layers)
      let result = try await tool.step(input, params) { progress in
        // A line arriving after its run ended must not bring the spinner back, nor land in the
        // next run's.
        Task { @MainActor [weak self] in
          guard let self, self.toolRunNumber == number, self.toolRun != nil else { return }
          self.toolRun = progress
        }
      }
      try Task.checkCancellation()
      // Another head, or a mask drawn while the tool ran: its result is not what is shown.
      let moved: LocalizedStringResource? =
        studio.steps.last?.file == head
        ? nil : .app("The image changed while the tool ran: nothing was recorded.")
      if let reason = moved ?? toolRefusal {
        failure = reason
        return false
      }
      try reported {
        try studio.apply(
          id, params: params, result: result.image, outputs: result.outputs,
          replacing: result.replaced)
      }
      recorded = true
      // The user's manual work becomes the recipe (R5), as for a GPU Apply.
      pipeline?.applied(id, params: params)
      // The report belongs to the panel that asked for it (not one reopened meanwhile).
      if self.panel === panel { toolReport = result.report }
    } catch {
      // A stopped tool may also surface as the tool's own failure: Stop is what happened.
      failure =
        error is CancellationError || Task.isCancelled
        ? .app("Stopped: nothing was recorded.") : UserFacingError(error).message
    }
    return recorded
  }

  /// A copy of `image` no one else holds: what a tool may take off the main actor.
  private nonisolated static func detached(_ image: AstroImage) -> sending AstroImage {
    AstroImage(
      width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
  }
}
