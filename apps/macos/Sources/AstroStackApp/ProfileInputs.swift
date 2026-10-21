package import ProcessKit
package import StackKit

extension ProfileProposal.Inputs {
  /// What the light sets of `inventory` say (card 0060).
  ///
  /// The camera is StackKit's colour model of the lights (mixed → unknown); OSC filters come from
  /// the clip-filter verdicts (both → the lanes `FilterSetLanes` splits, one only when every light
  /// set has that verdict), mono filters from the sets' filters (the scan already applied the
  /// filter map); the target when every set names the same one. Nothing is guessed from pixels.
  package nonisolated init(inventory: Inventory) {
    let lights = inventory.sets.filter { $0.key.type == .light }
    let objects = Set(lights.map(\.key.object).filter { !$0.isEmpty })
    let camera: Profile.Camera? =
      if lights.isEmpty { nil } else {
        switch inventory.colorModel {
        case .osc: .osc
        case .mono: .mono
        case .mixed: nil
        }
      }
    let filters: Profile.Filters? =
      switch camera {
      case .osc: Self.oscFilters(inventory, lights: lights)
      case .mono: Self.monoFilters(Set(lights.compactMap { Filter.token($0.key.filter) }))
      case nil: nil
      }
    self.init(object: objects.count == 1 ? objects.first : nil, camera: camera, filters: filters)
  }

  /// Both verdicts → lanes (StackKit's split); one verdict only when every light set has it.
  private nonisolated static func oscFilters(_ inventory: Inventory, lights: [FrameSet])
    -> Profile.Filters?
  {
    if FilterSetLanes.splits(inventory) { return .broadbandDualband }
    let verdicts = Set(lights.map { inventory.filterSets[$0.key.id] ?? .unknown })
    switch verdicts {
    case [.dualband]: return .dualband
    case [.broadband]: return .broadband
    default: return nil
    }
  }

  private nonisolated static func monoFilters(_ filters: Set<Filter>) -> Profile.Filters? {
    if filters.isSuperset(of: [.luminance, .red, .green, .blue]) {
      return filters.contains(.hydrogenAlpha) ? .lrgbHa : .lrgb
    }
    return !filters.isEmpty && filters.allSatisfy(\.isNarrowband) ? .narrowband : nil
  }
}
