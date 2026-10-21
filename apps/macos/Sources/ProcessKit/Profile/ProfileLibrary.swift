package import Foundation

/// The shipped profiles and the user's copies (card 0060).
///
/// Builtins are JSON resources of ProcessKit (`Profiles/`), read-only; a user's save always goes to
/// the user store (the project's `user_profiles`, through the closures), so a copy shadows the
/// builtin of the same id and the builtin stays offered, unchanged.
package struct ProfileLibrary {
  /// Every profile the user can pick: builtins, each replaced by the user's copy when there is
  /// one, then the user's own profiles; sorted by id.
  package let profiles: [Profile]
  /// The user copies that could not be used, by id, with why (shown, never silently dropped).
  package let rejected: [String: String]
  private let builtins: [Profile]
  private let save: (String, Data) throws -> Void

  /// The library over the builtins and the user's saved profiles (`user`: JSON by id).
  ///
  /// Saves go through `save`; `acceptsKnob` checks a copy's preprocessing knobs (StackKit's
  /// `KnobSchema`, which ProcessKit cannot import). A copy that does not load or check is left out
  /// and listed in `rejected`: one bad file never hides the other profiles.
  package init(
    registry: ProcessRegistry, user: () throws -> [String: Data],
    save: @escaping (String, Data) throws -> Void,
    acceptsKnob: (String, ParamValue) -> Bool = { _, _ in true }
  ) throws {
    let builtins = try Self.builtins(registry: registry)
    var copies: [Profile] = []
    var rejected: [String: String] = [:]
    for (id, data) in try user() {
      do {
        var profile = try Profile.load(data, registry: registry)
        if let knob = profile.preprocessing.knobs.first(where: { !acceptsKnob($0.key, $0.value) }) {
          throw ProfileError.unknownParameter("preprocessing", knob.key)
        }
        profile.isUserCopy = true
        copies.append(profile)
      } catch {
        rejected[id] = "\(error)"
      }
    }
    self.rejected = rejected
    let shadowed = Set(copies.map(\.id))
    self.builtins = builtins
    profiles = (builtins.filter { !shadowed.contains($0.id) } + copies).sorted { $0.id < $1.id }
    self.save = save
  }

  /// The profile `id` as the user has it (their copy first).
  package func profile(id: String) -> Profile? {
    profiles.first { $0.id == id }
  }

  /// The shipped profile `id`, whatever the user saved.
  package func builtin(id: String) -> Profile? {
    builtins.first { $0.id == id }
  }

  /// Saves `profile` as a user copy (never into the app's resources).
  package func save(_ profile: Profile) throws {
    try save(profile.id, profile.json())
  }

  /// The shipped profiles, from ProcessKit's `Profiles/` resources, sorted by id.
  package static func builtins(registry: ProcessRegistry) throws -> [Profile] {
    guard let folder = ProcessKitResources.bundle.url(forResource: "Profiles", withExtension: nil)
    else { throw ProfileError.malformed("Profiles missing from ProcessKit's resources") }
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { try Profile.load(Data(contentsOf: $0), registry: registry) }
  }

  /// The file of builtin `id` (read-only).
  package static func builtinURL(id: String) -> URL? {
    ProcessKitResources.bundle.url(forResource: "Profiles/\(id).json", withExtension: nil)
  }
}
