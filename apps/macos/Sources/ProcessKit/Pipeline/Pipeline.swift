/// An ordered list of recipes run over an image (card 0059, design §2, R5): PixInsight's
/// ProcessContainer, with breakpoints and locks.
///
/// A `stop` step halts the run before it, so the Studio shows that process with its recipe loaded
/// and the user adjusts it; a `locked` step keeps the output it was applied with when the pipeline
/// is replayed on the same image.
package struct Pipeline: Equatable, Sendable {
  /// The name it is saved under in the project (`pipelines.name`).
  package var name: String
  /// The steps, in order.
  package var steps: [PipelineStep]

  /// A pipeline `name` of `steps`.
  package init(name: String, steps: [PipelineStep]) {
    self.name = name
    self.steps = steps
  }

  /// Why the steps cannot run as ordered on a bundle with the `present` layers.
  ///
  /// A process the registry does not know (and no batch tool runs), a missing layer, or a linear
  /// step after a non-linear one: shown on the greyed step, never fixed silently.
  package func problems(
    registry: ProcessRegistry, batch: Set<String> = [], present: Set<LayerRole>
  ) -> [String] {
    let problems = stepProblems(registry: registry, batch: batch, present: present)
    return problems.enumerated().flatMap { index, reasons in
      let id = steps[index].recipe.processID
      // An unknown process is named by the reason itself.
      let label = registry.type(id: id) == nil ? "step \(index + 1)" : "step \(index + 1) (\(id))"
      return reasons.map { "\(label): \($0)" }
    }
  }

  /// The same reasons, one list per step (empty when the step can run): the sidebar greys each
  /// step with its own.
  package func stepProblems(
    registry: ProcessRegistry, batch: Set<String> = [], present: Set<LayerRole>
  ) -> [[String]] {
    var stretched = false
    var present = present
    return steps.map { step in
      let id = step.recipe.processID
      guard let type = registry.type(id: id) else {
        return batch.contains(id) ? [] : ["unknown process \(id)"]
      }
      var reasons: [String] = []
      if let reason = LayerRole.unavailableReason(requires: type.requires, present: present) {
        reasons.append(reason)
      }
      // A host tool's step runs only through its injected tool (card 0093): never its preview.
      if step.recipe.runsTool(as: type) {
        // A batch tool runs it here: a choice still to make (card 0140) is refused up front.
        if !batch.contains(id) {
          reasons.append("runs a host tool: apply it in the Studio")
        } else if let unchosen = step.recipe.unchosen(as: type).first {
          reasons.append("choose \(unchosen) first")
        }
      }
      if type.stage == .linear, stretched {
        reasons.append("a linear process after a non-linear one")
      }
      stretched = stretched || Self.leavesNonLinear(type)
      // A combination that can run makes the colour image the next steps need (card 0137).
      if type.makesColour, reasons.isEmpty { present.insert(.color) }
      return reasons
    }
  }
}

extension Pipeline {
  /// Whether the data are non-linear after `type`: the stretch takes linear data (stage
  /// `.linear`) and leaves it non-linear; a non-linear process needs it so (the Studio's
  /// catalogue reads the same rule, card 0087).
  package static func leavesNonLinear(_ type: any ImageProcess.Type) -> Bool {
    type.stage == .nonlinear || type.id == StretchProcess.id
  }
}

/// One step of a pipeline: a recipe, run automatically or as a breakpoint, maybe locked.
package struct PipelineStep: Equatable, Sendable {
  /// How the runner treats the step.
  package enum Mode: String, Codable, Sendable {
    /// Applied without stopping.
    case auto
    /// The run halts before it, the process loaded for the user.
    case stop
  }

  /// The process and its values.
  package var recipe: Recipe
  /// Auto or breakpoint.
  package var mode: Mode
  /// Kept as applied on replay, not re-run.
  package var locked: Bool

  /// A step running `recipe` in `mode`, `locked` or not.
  package init(recipe: Recipe, mode: Mode = .auto, locked: Bool = false) {
    self.recipe = recipe
    self.mode = mode
    self.locked = locked
  }
}

/// Why a pipeline step could not run.
package enum PipelineError: Error, Equatable, Sendable {
  /// No registered process and no batch tool has this id.
  case unknownProcess(String)
  /// `resume` was asked for a step the pipeline does not have.
  case noStep(Int)
  /// `resume` at `step`, but the history does not stand at that breakpoint (it holds
  /// `steps` steps, or the step is not a breakpoint): Continue would apply it to the wrong image.
  case notAtBreakpoint(step: Int, steps: Int)
  /// The step's values `ids` are refused by its process (unknown, wrong kind, not finite): the
  /// run stops rather than apply defaults the user never saw.
  case invalidValues(step: Int, ids: [String])
  /// A host-tool process (plate solving…) whose tool the caller did not inject.
  case toolMissing(String)
}
