/// The processes the Studio offers, by id.
///
/// Registration checks each schema, so a process
/// breaking a structural rule never reaches a panel.
package struct ProcessRegistry {
  /// The registered processes, in menu order.
  package let types: [any ImageProcess.Type]

  /// A registry of `types`; refuses an invalid process or a duplicate id.
  package init(_ types: [any ImageProcess.Type]) throws {
    var seen: Set<String> = []
    for type in types {
      guard seen.insert(type.id).inserted else { throw RegistryError.duplicate(id: type.id) }
      let problems = Self.problems(of: type)
      guard problems.isEmpty else { throw RegistryError.invalid(id: type.id, problems: problems) }
    }
    self.types = types
  }

  /// The processes shipped with the app, validated like any registry.
  ///
  /// Each ships fr+en help cards (`ProcessSchemaTests` gates both). E12 cards add theirs here, in menu order.
  package static func standard() throws -> Self {
    try Self([
      ChannelCombinationProcess.self, StretchProcess.self, LevelsProcess.self,
      BackgroundExtractionProcess.self, HDRProcess.self,
      EmissionScreensProcess.self, ColourBalanceProcess.self, SkyDesatProcess.self,
      CurvesProcess.self, SaturationProcess.self, StarRecompositionProcess.self,
      PlateSolveProcess.self, ColourCalibrationProcess.self, DenoiseProcess.self,
      GeometryProcess.self,
    ])
  }

  /// The ids of the processes that move pixels (`GeometricProcess`, card 0090).
  package var movingIDs: Set<String> {
    Set(types.filter { $0 is any GeometricProcess.Type }.map { $0.id })
  }

  /// Whether a step of `processID` with `params` moves the pixels: a geometric process off its
  /// identity (card 0106; recorded as `History.Step.movesPixels`).
  package func movesPixels(_ processID: String, params: ParamSet) -> Bool {
    guard let type = type(id: processID) as? any GeometricProcess.Type else { return false }
    return !type.isIdentity(params)
  }

  /// The ids, in menu order.
  package var ids: [String] { types.map { $0.id } }

  /// The process `id`, if registered.
  package func type(id: String) -> (any ImageProcess.Type)? {
    types.first { $0.id == id }
  }

  /// The rules the declaration of `type` breaks.
  ///
  /// An empty id or title, or `.px` parameters without `previewExactOnlyAt1to1` (pixel
  /// operators do not commute with the preview pyramid).
  package static func problems(of type: any ImageProcess.Type) -> [String] {
    var problems: [String] = []
    if type.id.isEmpty || type.title.isEmpty { problems.append("empty id or title") }
    problems += type.schema.problems
    let pixels = type.schema.pixelParameters
    if !pixels.isEmpty, !type.previewExactOnlyAt1to1 {
      problems.append(
        "has .px parameters (\(pixels.joined(separator: ", "))): declare previewExactOnlyAt1to1")
    }
    return problems
  }
}

/// Why a registry was refused.
package enum RegistryError: Error, Equatable, Sendable {
  /// Two processes share an id.
  case duplicate(id: String)
  /// A process's declaration breaks a rule.
  case invalid(id: String, problems: [String])
}
