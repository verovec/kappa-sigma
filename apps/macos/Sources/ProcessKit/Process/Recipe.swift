package import Foundation

/// A process and its values, saved as JSON (design §2, R5): replayable on another image, shared
/// between users. A newer app's file loads with warnings for what this version does not know.
package struct Recipe: Equatable, Sendable {
  /// The recipe format this version writes and reads.
  package static let schemaVersion = 1

  /// The process's id.
  package let processID: String
  /// Its values, in panel order.
  package let params: [ParamSet.Entry]

  /// A recipe of `processID` with `params`.
  package init(processID: String, params: ParamSet) {
    self.processID = processID
    self.params = params.entries
  }

  /// A loaded recipe: its values validated on the process's schema, and what was ignored.
  package struct Loaded: Sendable {
    /// The recipe as written in the file (known keys).
    package let recipe: Recipe
    /// The values, clamped onto the registered process's schema.
    package let params: ParamSet
    /// What was ignored, one sentence each.
    package let warnings: [String]
  }

  /// `{"schemaVersion": 1, "process": id, "params": [{"id", "value"}…]}`, sorted keys.
  package func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(File(schemaVersion: Self.schemaVersion, process: processID, params: params))
  }

  /// Reads `data` for a process of `registry`: unknown keys and parameters are warnings; an
  /// unknown process, a newer format or a malformed file is an error.
  package static func load(_ data: Data, registry: ProcessRegistry) throws(RecipeError) -> Loaded {
    let file: File
    let keys: [String]
    do {
      file = try JSONDecoder().decode(File.self, from: data)
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
      keys = object.keys.sorted()
    } catch {
      throw .malformed("\(error)")
    }
    guard file.schemaVersion <= schemaVersion else { throw .newerFormat(file.schemaVersion) }
    guard let type = registry.type(id: file.process) else { throw .unknownProcess(file.process) }
    var warnings = keys.filter { !File.keys.contains($0) }.map { "unknown key \($0) ignored" }
    let (params, rejected) = ParamSet.loading(file.params, onto: type.schema)
    warnings += rejected.map { entry in
      type.schema.spec(entry.id) == nil
        ? "parameter \(entry.id) ignored: not in \(file.process)"
        : "parameter \(entry.id) ignored: invalid value"
    }
    let recipe = Recipe(processID: file.process, params: params)
    return Loaded(recipe: recipe, params: params, warnings: warnings)
  }

  private init(processID: String, params: [ParamSet.Entry]) {
    self.processID = processID
    self.params = params
  }

  /// The JSON layout.
  private struct File: Codable {
    static let keys: Set<String> = ["schemaVersion", "process", "params"]
    let schemaVersion: Int
    let process: String
    let params: [ParamSet.Entry]
  }
}

/// Why a recipe file cannot be loaded.
package enum RecipeError: Error, Equatable, Sendable {
  /// Not a recipe (not JSON, or a missing field).
  case malformed(String)
  /// Written by a newer format version.
  case newerFormat(Int)
  /// No registered process has this id.
  case unknownProcess(String)
}
