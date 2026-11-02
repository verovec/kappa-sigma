package import FilterKit

/// An emission line the line processes read: a projection of FilterKit's narrowband filters
/// (card 0133) — the one list — with the parameter-id prefix, the panel name the schemas use and
/// the line's panel defaults; or an « Other line » slot bound to a layer kept as written (card
/// 0164, `custom(slot:layer:)`), read by the same code.
package struct EmissionLine: Hashable, Sendable, CaseIterable {
  /// The filter that isolates the line; `nil` for an « Other line » slot.
  package let filter: Filter?
  /// The bundle layer it reads.
  package let layerID: String
  /// The prefix of its parameter ids (`haBlack`, `oiiiOpacity`, `custom1Gain`…).
  package let prefix: String
  /// How panels write it.
  package let name: String
  /// Its panel defaults (`LinePanelDefaults`): a line without an entry is not a line here, and
  /// `LinePanelDefaultsTests` says so (the table's keys are exactly `Filter.narrowband`).
  let defaults: LinePanelDefaults

  /// The line of `filter`; `nil` for a filter outside `LinePanelDefaults` (every broadband one).
  package init?(_ filter: Filter) {
    guard let defaults = LinePanelDefaults.table[filter], let line = filter.line else { return nil }
    self.init(
      filter: filter, layerID: filter.rawValue, prefix: filter.rawValue.lowercased(),
      name: line.displayName, defaults: defaults)
  }

  private init(
    filter: Filter?, layerID: String, prefix: String, name: String, defaults: LinePanelDefaults
  ) {
    self.filter = filter
    self.layerID = layerID
    self.prefix = prefix
    self.name = name
    self.defaults = defaults
  }

  /// « Other line `slot` » reading the bundle layer `layer`, with the neutral defaults.
  package static func custom(slot: Int, layer: String) -> Self {
    Self(
      filter: nil, layerID: layer, prefix: slotPrefix(slot), name: slotName(slot),
      defaults: .other)
  }

  /// Every catalogued line, in display order.
  package static let allCases = Filter.narrowband.compactMap(Self.init)

  /// The bundle layers of every catalogued line.
  package static let layerIDs = Set(allCases.map(\.layerID))

  /// Whether the bundle layer `id` is a line layer, known or not (`NII-custom`).
  ///
  /// A line name (`Filter.isLineName`, the rule of StackKit's bundle roles) that is not a step
  /// role (card 0136).
  package static func isLineLayer(_ id: String) -> Bool {
    LayerRole(rawValue: id) == nil && Filter.isLineName(id)
  }

  /// The broadband layers among `layerIDs`, the planes a continuum subtraction may read: neither
  /// a line layer, known or not, nor a step role (mask, stars, background model) — card 0175.
  package static func broadband(in layerIDs: Set<String>) -> Set<String> {
    layerIDs.filter { LayerRole(rawValue: $0) == nil && !isLineLayer($0) }
  }

  /// The layer `id` as the panel writes it: a line's name, any other id as is (until 0139 words
  /// every layer).
  package static func name(ofLayer id: String) -> String {
    Filter(rawValue: id).flatMap(Self.init)?.name ?? id
  }

  /// The id of its parameter `name` (`Enabled`, `Black`…).
  package func id(_ name: String) -> String { prefix + name }

  /// The continuum scale the bundle fitted on this line's layer and the plane it was fitted
  /// against (`continuum_k`, `continuum_ref`); `nil` without both: a scale without its plane
  /// cannot be applied.
  package func continuumFit(in layerStats: [String: LayerStats]) -> (k: Double, reference: String)?
  {
    guard let stats = layerStats[layerID], let k = stats.continuumK,
      let reference = stats.continuumReference
    else { return nil }
    return (k, reference)
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prefix == rhs.prefix && lhs.layerID == rhs.layerID
  }
  package func hash(into hasher: inout Hasher) {
    hasher.combine(prefix)
    hasher.combine(layerID)
  }
}
