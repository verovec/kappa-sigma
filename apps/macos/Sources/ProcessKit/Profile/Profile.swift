/// A profile (card 0060, design §7, R5): for an object type, a filter composition and a camera,
/// the preprocessing mode and knobs, a pipeline of recipes, and why each value is what it is.
///
/// The shipped profiles are the PO's validated recipes (M 31 HaPlus, IC 1848 « doux », M 45);
/// they are starting points the user adjusts and saves as user copies, never hidden gates:
/// a profile sets values, nothing else.
package struct Profile: Equatable, Sendable {
  /// The camera a profile is for.
  package enum Camera: String, CaseIterable, Sendable {
    /// One-shot colour.
    case osc
    /// Monochrome with filters.
    case mono
  }

  /// The filters of the captures a profile is for.
  package enum Filters: String, CaseIterable, Sendable {
    /// OSC broadband only.
    case broadband
    /// OSC dual-band only.
    case dualband
    /// OSC broadband and dual-band nights (lanes).
    case broadbandDualband = "broadband+dualband"
    /// Mono L, R, G, B.
    case lrgb
    /// Mono L, R, G, B and Hα.
    case lrgbHa = "lrgb+ha"
    /// Mono narrowband (Hα, OIII, SII).
    case narrowband
  }

  /// The kind of object a profile is for.
  package enum ObjectType: String, CaseIterable, Sendable {
    /// A galaxy: a bright core, faint arms.
    case galaxy
    /// An emission nebula.
    case emissionNebula = "emission-nebula"
    /// A star cluster or a reflection nebula.
    case cluster
    /// Any nebula (narrowband palettes).
    case nebula
  }

  /// A text in English and French.
  package struct Text: Equatable, Sendable {
    /// English.
    package let english: String
    /// French.
    package let french: String

    /// `english` and `french`.
    package init(english: String, french: String) {
      self.english = english
      self.french = french
    }

    /// The text for `language` (`fr`, else English).
    package func text(language: String) -> String { language == "fr" ? french : english }
  }

  /// One step: a process with the values the profile sets, each with its reason.
  package struct Step: Equatable, Sendable {
    /// The process and all its values (defaults where the profile sets none).
    package private(set) var recipe: Recipe
    /// The values the profile sets.
    package private(set) var values: [String: ParamValue]
    /// Why each value is what it is.
    package private(set) var why: [String: Text]
    /// Auto or breakpoint.
    package let mode: PipelineStep.Mode
    /// Kept as applied on replay.
    package let locked: Bool
    /// The process's parameters.
    let schema: ParamSchema

    /// A step of a process of `schema` with `values` (validated, never clamped: `strict`).
    init(
      processID: String, schema: ParamSchema, values: [String: ParamValue], why: [String: Text],
      mode: PipelineStep.Mode, locked: Bool
    ) throws {
      var params = ParamSet(schema: schema)
      for (id, value) in values.sorted(by: { $0.key < $1.key }) {
        guard let spec = schema.spec(id) else { throw ProfileError.unknownParameter(processID, id) }
        guard try spec.validated(value) == value else {
          throw ProfileError.outOfBounds(processID, id)
        }
        try params.set(id, value)
      }
      self.recipe = Recipe(processID: processID, params: params)
      self.values = values
      self.why = why
      self.mode = mode
      self.locked = locked
      self.schema = schema
    }

    /// Sets `id` to `value` (validated and clamped, as a panel would).
    mutating func set(_ id: String, _ value: ParamValue) throws {
      var params = ParamSet.loading(recipe.params, onto: schema).params
      try params.set(id, value)
      values[id] = params[id]
      recipe = Recipe(processID: recipe.processID, params: params)
      // A value the profile did not set is the user's: it says so, and the copy stays readable.
      if why[id] == nil { why[id] = Profile.userValue }
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.recipe == rhs.recipe && lhs.values == rhs.values && lhs.why == rhs.why
        && lhs.mode == rhs.mode && lhs.locked == rhs.locked
    }
  }

  /// The preprocessing a profile sets: the preset mode and knob values (0070's wire keys).
  package struct Preprocessing: Equatable, Sendable {
    /// `deepsky` or `nebula`.
    package let mode: String
    /// Knob values by wire key.
    package let knobs: [String: ParamValue]
    /// Why each knob is what it is.
    package let why: [String: Text]
  }

  /// Stable id (the JSON file name).
  package let id: String
  /// The object type.
  package let object: ObjectType
  /// The camera.
  package let camera: Camera
  /// The filter compositions it fits.
  package let filters: [Filters]
  /// Its name in the panel.
  package let title: Text
  /// Targets it was validated on (`M 31`): a capture of one of them proposes it.
  package let examples: [String]
  /// The preprocessing it sets.
  package let preprocessing: Preprocessing
  /// Its steps, in order.
  package internal(set) var steps: [Step]
  /// A user's saved copy (shadows the builtin of the same id, never overwrites it).
  package internal(set) var isUserCopy = false

  /// The pipeline the Studio runs (0059).
  package var pipeline: Pipeline {
    Pipeline(
      name: id,
      steps: steps.map { PipelineStep(recipe: $0.recipe, mode: $0.mode, locked: $0.locked) })
  }

  /// The « why » of a value the user set on a copy.
  package static let userValue = Text(
    english: "Your value, set on this copy.", french: "Votre valeur, réglée sur cette copie.")

  /// Sets value `id` of step `index` (validated and clamped, as a panel would).
  package mutating func set(_ id: String, to value: ParamValue, inStep index: Int) throws {
    guard steps.indices.contains(index) else { throw PipelineError.noStep(index) }
    try steps[index].set(id, value)
  }
}

/// Why a profile file cannot be used.
package enum ProfileError: Error, Equatable, Sendable {
  /// Not a profile (not JSON, a missing field, an unknown camera, filters, object or mode).
  case malformed(String)
  /// Written by a newer format version.
  case newerFormat(Int)
  /// A step of a process the registry does not have.
  case unknownProcess(String)
  /// A value for a parameter the process does not have.
  case unknownParameter(String, String)
  /// A value outside its parameter's bounds or options (a profile is never clamped silently).
  case outOfBounds(String, String)
  /// A value or knob without its English and French « why ».
  case missingWhy(String)
}
