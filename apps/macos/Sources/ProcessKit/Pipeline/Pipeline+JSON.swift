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

  /// Reads `data` for the processes of `registry` and the batch tools of `batch` (their
  /// parameter schemas by id).
  ///
  /// Unknown keys, parameters and clamped values are warnings (R2: the user sees each change);
  /// a newer format, a malformed file, an unknown process or mode is a `PipelineFileError`.
  package static func load(
    _ data: Data, registry: ProcessRegistry, batch: [String: ParamSchema] = [:]
  ) throws -> Loaded {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let versionNumber = object["schemaVersion"] as? NSNumber,
      CFGetTypeID(versionNumber) != CFBooleanGetTypeID(), versionNumber.intValue >= 1,
      let name = object["name"] as? String,
      let steps = object["steps"] as? [[String: Any]]
    else { throw PipelineFileError.malformed("not a pipeline file") }
    let version = versionNumber.intValue
    guard version <= schemaVersion else { throw PipelineFileError.newerFormat(version) }
    var warnings = object.keys.sorted().filter { !keys.contains($0) }
      .map { "unknown key \($0) ignored" }
    var loaded: [PipelineStep] = []
    for (index, step) in steps.enumerated() {
      let (pipelineStep, stepWarnings): (PipelineStep, [String])
      do {
        (pipelineStep, stepWarnings) = try loadStep(step, registry: registry, batch: batch)
      } catch {
        throw PipelineFileError.step(index + 1, "\(error)")
      }
      loaded.append(pipelineStep)
      warnings += stepWarnings.map { "step \(index + 1): \($0)" }
    }
    return Loaded(pipeline: Pipeline(name: name, steps: loaded), warnings: warnings)
  }

  private static func loadStep(
    _ step: [String: Any], registry: ProcessRegistry, batch: [String: ParamSchema]
  ) throws -> (PipelineStep, [String]) {
    guard let recipeObject = step["recipe"] as? [String: Any],
      let modeName = step["mode"] as? String, let mode = PipelineStep.Mode(rawValue: modeName),
      let lockedValue = step["locked"] as? NSNumber,
      CFGetTypeID(lockedValue) == CFBooleanGetTypeID()
    else { throw PipelineFileError.malformed("a step needs a recipe, an auto|stop mode, locked") }
    let warnings = step.keys.sorted().filter { !stepKeys.contains($0) }
      .map { "unknown key \($0) ignored" }
    let (recipe, recipeWarnings) = try loadRecipe(recipeObject, registry: registry, batch: batch)
    return (
      PipelineStep(recipe: recipe, mode: mode, locked: lockedValue.boolValue),
      warnings + recipeWarnings
    )
  }

  /// A step's recipe and its warnings, read like a recipe file.
  ///
  /// A registered process on its schema, a batch tool on the schema `batch` gives; the values
  /// kept are the clamped ones the warnings describe.
  private static func loadRecipe(
    _ object: [String: Any], registry: ProcessRegistry, batch: [String: ParamSchema]
  ) throws -> (Recipe, [String]) {
    let data = try JSONSerialization.data(withJSONObject: object)
    let recipe = try Recipe.load(data) { registry.type(id: $0)?.schema ?? batch[$0] }
    return (Recipe(processID: recipe.recipe.processID, params: recipe.params), recipe.warnings)
  }
}

/// Why a pipeline file cannot be loaded.
package enum PipelineFileError: Error, Equatable, Sendable {
  /// Not a pipeline (not JSON, a missing field, an unknown mode).
  case malformed(String)
  /// Written by a newer format version.
  case newerFormat(Int)
  /// Step `n` (from 1) could not be read: why.
  case step(Int, String)
}
