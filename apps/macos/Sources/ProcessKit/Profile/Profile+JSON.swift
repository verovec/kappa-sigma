package import Foundation

/// Profiles as JSON (card 0060): `{"schemaVersion": 1, "id", "object", "camera", "filters",
/// "title": {"en", "fr"}, "examples", "preprocessing": {"mode", "knobs", "why"}, "steps":
/// [{"process", "mode", "locked", "values", "why": {id: {"en", "fr"}}}]}`.
///
/// Read strictly: a profile is the PO's values as validated, so an unknown process or parameter, a
/// value outside its bounds or a value without its « why » refuses the file — never a silent fix.
extension Profile {
  /// The profile format this version writes and reads.
  package static let schemaVersion = 1

  /// Reads `data`, every step validated on the process of `registry`.
  package static func load(_ data: Data, registry: ProcessRegistry) throws -> Profile {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ProfileError.malformed("not JSON")
    }
    let version = JSONScalar.int(object["schemaVersion"]) ?? 0
    guard version >= 1 else { throw ProfileError.malformed("schemaVersion") }
    guard version <= schemaVersion else { throw ProfileError.newerFormat(version) }
    guard let id = object["id"] as? String,
      let type = (object["object"] as? String).flatMap(ObjectType.init(rawValue:)),
      let camera = (object["camera"] as? String).flatMap(Camera.init(rawValue:)),
      let filterNames = object["filters"] as? [String],
      let title = text(object["title"]), let examples = object["examples"] as? [String],
      let preprocessing = object["preprocessing"] as? [String: Any],
      let steps = object["steps"] as? [[String: Any]]
    else { throw ProfileError.malformed("missing or unknown id, object, camera, title or steps") }
    let filters = try filterNames.map { name in
      guard let value = Filters(rawValue: name) else { throw ProfileError.malformed(name) }
      return value
    }
    return Profile(
      id: id, object: type, camera: camera, filters: filters, title: title, examples: examples,
      preprocessing: try loadPreprocessing(preprocessing),
      steps: try steps.map { try loadStep($0, registry: registry) })
  }

  /// The JSON of the profile, keys sorted.
  package func json() throws -> Data {
    let object: [String: Any] = [
      "schemaVersion": Self.schemaVersion, "id": id, "object": object.rawValue,
      "camera": camera.rawValue, "filters": filters.map(\.rawValue), "title": Self.json(title),
      "examples": examples,
      "preprocessing": [
        "mode": preprocessing.mode, "knobs": try preprocessing.knobs.mapValues(Self.json),
        "why": preprocessing.why.mapValues(Self.json),
      ],
      "steps": try steps.map { step -> [String: Any] in
        [
          "process": step.recipe.processID, "mode": step.mode.rawValue, "locked": step.locked,
          "values": try step.values.mapValues(Self.json), "why": step.why.mapValues(Self.json),
        ]
      },
    ]
    return try JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  }

  private static func loadStep(_ step: [String: Any], registry: ProcessRegistry) throws -> Step {
    guard let id = step["process"] as? String,
      let mode = (step["mode"] as? String).flatMap(PipelineStep.Mode.init(rawValue:)),
      let locked = JSONScalar.bool(step["locked"]), let values = step["values"] as? [String: Any],
      let whys = step["why"] as? [String: Any]
    else { throw ProfileError.malformed("a step needs process, mode, locked, values, why") }
    guard let type = registry.type(id: id) else { throw ProfileError.unknownProcess(id) }
    let why = try notes(whys, for: Array(values.keys), context: id)
    return try Step(
      processID: id, schema: type.schema, values: try values.mapValues(value), why: why,
      mode: mode, locked: locked)
  }

  private static func loadPreprocessing(_ object: [String: Any]) throws -> Preprocessing {
    guard let mode = object["mode"] as? String, ["deepsky", "nebula"].contains(mode),
      let knobs = object["knobs"] as? [String: Any], let whys = object["why"] as? [String: Any]
    else { throw ProfileError.malformed("preprocessing needs mode deepsky|nebula, knobs, why") }
    return Preprocessing(
      mode: mode, knobs: try knobs.mapValues(value),
      why: try notes(whys, for: Array(knobs.keys), context: "preprocessing"))
  }

  /// The « why » of every id in `ids`, each with both languages.
  private static func notes(_ object: [String: Any], for ids: [String], context: String) throws
    -> [String: Text]
  {
    var notes: [String: Text] = [:]
    for id in ids {
      guard let note = text(object[id]), !note.english.isEmpty, !note.french.isEmpty else {
        throw ProfileError.missingWhy("\(context).\(id)")
      }
      notes[id] = note
    }
    return notes
  }

  private static func text(_ any: Any?) -> Text? {
    guard let object = any as? [String: Any], let english = object["en"] as? String,
      let french = object["fr"] as? String
    else { return nil }
    return Text(english: english, french: french)
  }

  private static func json(_ text: Text) -> [String: String] {
    ["en": text.english, "fr": text.french]
  }

  private static func value(_ any: Any) throws -> ParamValue {
    let data = try JSONSerialization.data(withJSONObject: any, options: .fragmentsAllowed)
    return try JSONDecoder().decode(ParamValue.self, from: data)
  }

  private static func json(_ value: ParamValue) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
  }
}
