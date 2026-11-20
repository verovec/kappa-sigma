/// Card 0194: a kept profile's combination is fitted to the stack before it becomes step 0. A
/// profile is chosen at import, the layers are only known after the run: a slot whose layer the
/// stack lacks — or holds without the colour plane asked (card 0195) — takes the source the stack
/// opens on, and the row says so (R2).
extension ChannelCombinationProcess {
  /// Why a row no longer holds the profile's source; the note's subject names the layer asked.
  package static let profileReason = "the profile asks for a layer the stack lacks"
  /// The same, when the stack holds the layer but not the colour plane the profile named.
  package static let profilePlaneReason =
    "the profile asks for a colour plane of a layer that has none"

  /// `profile` fitted to a bundle of `planes`, with the slots that lost their source.
  ///
  /// Every slot whose source the bundle can read (`unavailableReasons(_:layerIDs:planes:)`: the
  /// layer exists, with the plane named) is kept, each other takes the source
  /// `initialParams(planes:)` gives that slot; `dropped` lists them in slot order. Nothing dropped
  /// returns `profile` itself — weights, black points and L opacity are the profile's in every
  /// case.
  package static func reconciled(profile: ParamSet, planes: [String: Int]) throws
    -> (params: ParamSet, dropped: [String])
  {
    let lacking = unavailableReasons(profile, layerIDs: Set(planes.keys), planes: planes)
    let dropped = slotSources.filter { lacking[$0] != nil }
    guard !dropped.isEmpty else { return (profile, []) }
    let opening = try initialParams(planes: planes)
    var params = profile
    for slot in dropped { try params.set(slot, .choice(opening.choice(slot))) }
    return (params, dropped)
  }

  /// The rows of `params` that no longer hold what `profile` asked, by parameter id.
  ///
  /// A row is noted when the bundle cannot read the source the profile named there — the layer
  /// is absent, or holds no colour plane — with that layer as the panel writes it, for as long
  /// as the row holds another source. `planes` as `reconciled` got them: without, only absence
  /// is judged.
  package static func profileNotes(
    profile: ParamSet, params: ParamSet, layerIDs: Set<String>, planes: [String: Int] = [:]
  ) -> [String: RowNote] {
    unavailableReasons(profile, layerIDs: layerIDs, planes: planes)
      .filter { params.choice($0.key) != profile.choice($0.key) }
      .mapValues {
        RowNote(
          reason: $0.reason == planeReason ? profilePlaneReason : profileReason,
          subject: $0.subject)
      }
  }
}
