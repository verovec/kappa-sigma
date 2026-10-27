package import FilterKit

/// An emission line the line processes read: a projection of FilterKit's narrowband filters
/// (card 0133) — the one list — with the parameter-id prefix, the panel name the schemas use and
/// the line's panel defaults.
package struct EmissionLine: Hashable, Sendable, CaseIterable {
  /// The filter that isolates the line.
  package let filter: Filter
  /// Its physics (FilterKit).
  package let line: Filter.Line
  /// Its panel defaults (`LinePanelDefaults`): a line without an entry is not a line here, and
  /// `LinePanelDefaultsTests` says so (the table's keys are exactly `Filter.narrowband`).
  let defaults: LinePanelDefaults

  /// The line of `filter`; `nil` for a filter outside `LinePanelDefaults` (every broadband one).
  package init?(_ filter: Filter) {
    guard let defaults = LinePanelDefaults.table[filter], let line = filter.line else { return nil }
    self.filter = filter
    self.line = line
    self.defaults = defaults
  }

  /// Every line, in display order.
  package static let allCases = Filter.narrowband.compactMap(Self.init)

  /// The bundle layer it reads.
  package var layerID: String { filter.rawValue }

  /// The bundle layers of every line.
  package static let layerIDs = Set(allCases.map(\.layerID))

  /// Whether the bundle layer `id` is a line layer, known or not (`NII-custom`): a line name
  /// (`Filter.isLineName`, the rule of StackKit's bundle roles) that is not a step role (card 0136).
  package static func isLineLayer(_ id: String) -> Bool {
    LayerRole(rawValue: id) == nil && Filter.isLineName(id)
  }

  /// The prefix of its parameter ids (`haBlack`, `oiiiOpacity`…).
  package var prefix: String { filter.rawValue.lowercased() }

  /// How panels write it.
  package var name: String { line.displayName }

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

  package static func == (lhs: Self, rhs: Self) -> Bool { lhs.filter == rhs.filter }
  package func hash(into hasher: inout Hasher) { hasher.combine(filter) }
}
