package import Foundation

/// A process and its values, saved as JSON (design §2, R5).
///
/// Replayable on another image, shared between users. A newer app's file loads with warnings for what this version does not know.
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
    return try encoder.encode(
      File(schemaVersion: Self.schemaVersion, process: processID, params: params))
  }

  /// Reads `data` for a process of `registry`.
  ///
  /// What this version cannot use as written is a warning (R2: the user sees every change):
  /// unknown keys, unknown or invalid parameters, values clamped into today's bounds. An unknown
  /// process, a newer format or a malformed file is a `RecipeError`.
  package static func load(_ data: Data, registry: ProcessRegistry) throws -> Loaded {
    let file: File
    let object: [String: Any]
    do {
      file = try JSONDecoder().decode(File.self, from: data)
      object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
      throw RecipeError.malformed("\(error)")
    }
    guard file.schemaVersion <= schemaVersion else {
      throw RecipeError.newerFormat(file.schemaVersion)
    }
    guard let type = registry.type(id: file.process) else {
      throw RecipeError.unknownProcess(file.process)
    }
    var warnings = object.keys.sorted().filter { !File.keys.contains($0) }
      .map { "unknown key \($0) ignored" }
    let entryKeys = (object["params"] as? [[String: Any]] ?? []).map { Set($0.keys) }
    var params = ParamSet(schema: type.schema)
    for (index, entry) in file.params.enumerated() {
      let extra = index < entryKeys.count ? entryKeys[index].subtracting(["id", "value"]) : []
      warnings += extra.sorted().map { "parameter \(entry.id): unknown key \($0) ignored" }
      warnings += apply(entry, to: &params, process: file.process)
    }
    return Loaded(
      recipe: Self(processID: file.process, params: params), params: params, warnings: warnings)
  }

  /// Sets `entry` on `params`; the warning when it is ignored or clamped.
  private static func apply(
    _ entry: ParamSet.Entry, to params: inout ParamSet, process: String
  ) -> [String] {
    do {
      try params.set(entry.id, entry.value)
    } catch ParamError.unknown {
      return ["parameter \(entry.id) ignored: not in \(process)"]
    } catch {
      return ["parameter \(entry.id) ignored: invalid value"]
    }
    if case .number(let stored) = entry.value, case .number(let kept)? = params[entry.id],
      kept != stored
    {
      return ["parameter \(entry.id) clamped from \(stored) to \(kept)"]
    }
    if case .points(let stored) = entry.value, case .points(let kept)? = params[entry.id],
      kept != stored
    {
      return ["parameter \(entry.id): curve points clamped into [0, 1] or reordered"]
    }
    return []
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
