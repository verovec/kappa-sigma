package import Foundation

// MARK: - Pipelines (card 0059) and user profiles (card 0060)

extension ProjectStore {
  /// The names of the saved pipelines, sorted.
  package func pipelineNames() throws -> [String] {
    try names(in: .pipelines)
  }

  /// The JSON of the pipeline `name` (as ProcessKit's `Pipeline.json()` wrote it), `nil` when
  /// none has that name.
  package func pipeline(named name: String) throws -> Data? {
    try body(named: name, in: .pipelines)
  }

  /// Saves `json` as the pipeline `name` (« Save pipeline as… »); an existing one of that name
  /// is overwritten, keeping its row and `created_at`.
  package func savePipeline(named name: String, json: Data) throws {
    try save(json, named: name, in: .pipelines)
  }

  /// Deletes the pipeline `name` (nothing when there is none).
  package func deletePipeline(named name: String) throws {
    try delete(named: name, in: .pipelines)
  }

  /// The user's profile copies (ProcessKit `Profile.json()`), by profile id.
  package func userProfiles() throws -> [String: Data] {
    var profiles: [String: Data] = [:]
    for id in try names(in: .userProfiles) {
      profiles[id] = try body(named: id, in: .userProfiles)
    }
    return profiles
  }

  /// Saves the user's copy of profile `id` (never touches the shipped profile of that id).
  package func saveUserProfile(id: String, json: Data) throws {
    try save(json, named: id, in: .userProfiles)
  }

  /// Deletes the user's copy of profile `id`: the shipped one shows again.
  package func deleteUserProfile(id: String) throws {
    try delete(named: id, in: .userProfiles)
  }
}
