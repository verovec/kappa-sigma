package import ProcessKit
package import StackKit

extension ProfileProposal.Inputs {
  /// What the light sets of `inventory` say (card 0060).
  ///
  /// The camera (every set colour → OSC, none → mono, both → unknown), the filter composition
  /// (OSC: the clip-filter verdicts; mono: the filters), the target (when every set names the same
  /// one). Nothing is guessed from pixels.
  package nonisolated init(inventory: Inventory) {
    let lights = inventory.sets.filter { $0.key.type == .light }
    let objects = Set(lights.map(\.key.object).filter { !$0.isEmpty })
    let camera: Profile.Camera? =
      if lights.isEmpty { nil } else if lights.allSatisfy(\.key.color) {
        .osc
      } else if lights.allSatisfy({ !$0.key.color }) { .mono } else { nil }
    let filters: Profile.Filters? =
      switch camera {
      case .osc:
        Self.oscFilters(lights.compactMap { inventory.filterSets[$0.key.id] }, sets: lights.count)
      case .mono: Self.monoFilters(Set(lights.compactMap { Filter(rawValue: $0.key.filter) }))
      case nil: nil
      }
    self.init(object: objects.count == 1 ? objects.first : nil, camera: camera, filters: filters)
  }

  /// Both verdicts → lanes; one verdict only when every light set has one.
  private nonisolated static func oscFilters(_ verdicts: [FilterSet], sets: Int) -> Profile.Filters?
  {
    let (broadband, dualband) = (verdicts.contains(.broadband), verdicts.contains(.dualband))
    if broadband && dualband { return .broadbandDualband }
    guard verdicts.count == sets else { return nil }
    if dualband { return .dualband }
    return broadband ? .broadband : nil
  }

  private nonisolated static func monoFilters(_ filters: Set<Filter>) -> Profile.Filters? {
    if filters.isSuperset(of: [.luminance, .red, .green, .blue]) {
      return filters.contains(.hydrogenAlpha) ? .lrgbHa : .lrgb
    }
    return !filters.isEmpty && filters.allSatisfy(\.isNarrowband) ? .narrowband : nil
  }
}
