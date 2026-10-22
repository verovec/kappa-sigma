/// What one run stacks (card 0095): the lights of one object, by light-set id.
///
/// Every calibration set of the inventory travels with the run (flats per night, 0047), so two
/// objects imported together stack as two runs, each with the shared calibration — never merged
/// or picked by majority in silence (R2; the legacy engine stacked the « dominant object »).
package struct RunScope: Equatable, Sendable, Codable {
  /// The `OBJECT` the lights carry; `""` for unnamed lights (an object of their own).
  package var object: String
  /// The light sets stacked (`SetKey.id`), in the scan's order.
  package var setIDs: [String]
  /// How many lights those sets hold when the scope was made (the picker's « n lights »).
  package var lights: Int

  /// A scope of `object` over `setIDs` holding `lights` frames.
  package init(object: String, setIDs: [String], lights: Int) {
    self.object = object
    self.setIDs = setIDs
    self.lights = lights
  }

  private enum CodingKeys: String, CodingKey {
    case object, lights
    case setIDs = "set_ids"
  }

  /// One scope per object of `inventory`, objects in name order, each with every light set of
  /// its object in the scan's order; none without a light.
  package static func scopes(of inventory: Inventory) -> [Self] {
    var scopes: [String: Self] = [:]
    for set in inventory.sets where set.key.type == .light {
      var scope = scopes[set.key.object] ?? Self(object: set.key.object, setIDs: [], lights: 0)
      scope.setIDs.append(set.key.id)
      scope.lights += set.count
      scopes[set.key.object] = scope
    }
    return scopes.keys.sorted().compactMap { scopes[$0] }
  }

  /// The light sets of this object `inventory` holds that the scope does not list: a scan that
  /// moved since the series were chosen (a night added, a grouping changed), never stacked in
  /// silence.
  package func unlistedSets(in inventory: Inventory) -> [String] {
    let listed = Set(setIDs)
    return inventory.sets.filter { $0.key.type == .light && $0.key.object == object }
      .map(\.key.id).filter { !listed.contains($0) }
  }
}

extension Inventory {
  /// The frames `scope` stacks: everything but the lights of the other objects.
  ///
  /// The sets and their ids stay exactly as the scan grouped them (`subset` regroups and may drop
  /// a night from the keys), so every override and verdict stored under an id still applies;
  /// frames in no set (unknown, video) stay as well. Verdicts of dropped sets go. A scope none of
  /// whose sets the scan has leaves no light: `Preprocessor.plan` refuses it before anything runs.
  package func scoped(_ scope: RunScope) -> Inventory {
    let wanted = Set(scope.setIDs)
    let kept = sets.filter { $0.key.type != .light || wanted.contains($0.key.id) }
    let dropped = Set(
      sets.filter { $0.key.type == .light && !wanted.contains($0.key.id) }.flatMap(\.indices))
    let indices = frames.indices.filter { !dropped.contains($0) }
    var position: [Int: Int] = [:]
    for (new, old) in indices.enumerated() { position[old] = new }
    var out = Inventory(root: root, frames: indices.map { frames[$0] })
    out.warnings = warnings
    out.channelDetection = channelDetection
    out.colorModel = colorModel
    out.sets = kept.map { set in
      var set = set
      set.indices = set.indices.compactMap { position[$0] }
      return set
    }
    let keptIDs = Set(out.sets.map(\.key.id))
    out.filterSets = filterSets.filter { keptIDs.contains($0.key) }
    out.sessions = SessionInfo.summary(out.frames)
    return out
  }
}
