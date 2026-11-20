/// Card 0194: a kept profile's combination is fitted to the stack before it becomes step 0. A
/// profile is chosen at import, the layers are only known after the run: a slot whose layer the
/// stack lacks takes the source the stack opens on, and the row says so (R2).
extension ChannelCombinationProcess {
  /// Why a row no longer holds the profile's source; the note's subject names the layer asked.
  package static let profileReason = "the profile asks for a layer the stack lacks"

  /// `profile` fitted to a bundle of `planes`, with the slots that lost their source.
  ///
  /// Every slot whose source the bundle holds is kept, each other takes the source
  /// `initialParams(planes:)` gives that slot; `dropped` lists them in slot order. Nothing dropped
  /// returns `profile` itself — weights, black points and L opacity are the profile's in every
  /// case.
  package static func reconciled(profile: ParamSet, planes: [String: Int]) throws
    -> (params: ParamSet, dropped: [String])
  {
    let lacking = unavailableReasons(profile, layerIDs: Set(planes.keys))
    let dropped = slotSources.filter { lacking[$0] != nil }
    guard !dropped.isEmpty else { return (profile, []) }
    let opening = try initialParams(planes: planes)
    var params = profile
    for slot in dropped { try params.set(slot, .choice(opening.choice(slot))) }
    return (params, dropped)
  }

  /// The rows of `params` that no longer hold what `profile` asked, by parameter id.
  ///
  /// A row is noted when the bundle lacks the layer the profile named there, with that layer as
  /// the panel writes it, for as long as the row holds another source.
  package static func profileNotes(profile: ParamSet, params: ParamSet, layerIDs: Set<String>)
    -> [String: RowNote]
  {
    unavailableReasons(profile, layerIDs: layerIDs)
      .filter { params.choice($0.key) != profile.choice($0.key) }
      .mapValues { RowNote(reason: profileReason, subject: $0.subject) }
  }
}
