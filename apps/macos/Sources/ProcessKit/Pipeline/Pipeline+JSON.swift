package import Foundation

/// Pipelines as JSON (card 0059): `{"schemaVersion": 1, "name", "steps": [{"recipe": <a recipe
/// file>, "mode": "auto"|"stop", "locked"}]}` — each recipe in its own format, so a step reads and
/// warns exactly like a recipe file.
extension Pipeline {
  /// The pipeline format this version writes and reads.
  package static let schemaVersion = 1

  private static let keys: Set<String> = ["schemaVersion", "name", "steps"]
  private static let stepKeys: Set<String> = ["recipe", "mode", "locked"]

  /// A loaded pipeline: its recipes validated on the registry, and what was ignored or clamped.
  package struct Loaded: Sendable {
    /// The pipeline, values clamped onto today's schemas.
    package let pipeline: Pipeline
    /// What was ignored or changed, one sentence each.
    package let warnings: [String]
  }

  /// The JSON of the pipeline, keys sorted.
  package func json() throws -> Data {
    let steps = try steps.map { step -> [String: Any] in
      [
        "recipe": try JSONSerialization.jsonObject(with: step.recipe.json()),
        "mode": step.mode.rawValue, "locked": step.locked,
      ]
    }
    let object: [String: Any] = [
      "schemaVersion": Self.schemaVersion, "name": name, "steps": steps,
    ]
    return try JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  }

  /// Reads `data` for the processes of `registry`.
  ///
  /// Unknown keys, parameters and clamped values are warnings (R2: the user sees each change);
  /// a newer format, a malformed file, an unknown process or mode is a `PipelineFileError`.
  package static func load(_ data: Data, registry: ProcessRegistry) throws -> Loaded {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let version = object["schemaVersion"] as? Int, let name = object["name"] as? String,
      let steps = object["steps"] as? [[String: Any]]
    else { throw PipelineFileError.malformed("not a pipeline file") }
    guard version <= schemaVersion else { throw PipelineFileError.newerFormat(version) }
    var warnings = object.keys.sorted().filter { !keys.contains($0) }
      .map { "unknown key \($0) ignored" }
    var loaded: [PipelineStep] = []
    for (index, step) in steps.enumerated() {
      let (pipelineStep, stepWarnings) = try loadStep(step, registry: registry)
      loaded.append(pipelineStep)
      warnings += stepWarnings.map { "step \(index + 1): \($0)" }
    }
    return Loaded(pipeline: Pipeline(name: name, steps: loaded), warnings: warnings)
  }

  private static func loadStep(_ step: [String: Any], registry: ProcessRegistry) throws
    -> (PipelineStep, [String])
  {
    guard let recipeObject = step["recipe"],
      let modeName = step["mode"] as? String, let mode = PipelineStep.Mode(rawValue: modeName),
      let locked = step["locked"] as? Bool
    else { throw PipelineFileError.malformed("a step needs a recipe, an auto|stop mode, locked") }
    let recipe = try Recipe.load(
      JSONSerialization.data(withJSONObject: recipeObject), registry: registry)
    let warnings =
      step.keys.sorted().filter { !stepKeys.contains($0) }.map { "unknown key \($0) ignored" }
      + recipe.warnings
    return (
      PipelineStep(
        recipe: Recipe(processID: recipe.recipe.processID, params: recipe.params), mode: mode,
        locked: locked),
      warnings
    )
  }
}

/// Why a pipeline file cannot be loaded.
package enum PipelineFileError: Error, Equatable, Sendable {
  /// Not a pipeline (not JSON, a missing field, an unknown mode).
  case malformed(String)
  /// Written by a newer format version.
  case newerFormat(Int)
}
