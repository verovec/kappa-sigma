/// The calibration a run would apply, per light channel, without stacking anything
/// (`calib.CalibPreview` + `SuggestForInventory`): the data behind the Import calibration panel.
package struct CalibrationPreview: Equatable, Sendable {
  /// One master proposed for a light channel in a role; `id` is what the user sends back to
  /// exclude exactly this suggestion.
  package struct Suggestion: Equatable, Sendable {
    package var id: String
    package var role: CalibrationRole
    package var master: CalibrationMaster
    /// A master the run would BUILD from the capture's own frames (no path yet).
    package var fromCapture: Bool { master.path.isEmpty }
  }

  /// One light set and what would calibrate it.
  package struct Channel: Equatable, Sendable {
    package var key: SetKey
    package var suggestions: [Suggestion]
    package var notes: [String]
    package var filter: String { key.filter }
    package var session: String { key.session }
  }

  package var channels: [Channel]

  /// Matches every light set against `masters` (normally `candidates`) through the same pool the
  /// run uses: masters from another sensor are excluded first, under `force` too; `excluded`
  /// suggestion ids are dropped as the run drops them (`calib_exclude`).
  package init(
    inventory: Inventory, masters: [CalibrationMaster], excluded: [String] = [],
    force: Bool = false
  ) {
    channels = inventory.sets.filter { $0.key.type == .light }.map { set in
      let pool = DimensionGuard.keepMatching(masters, lightPath: set.frames.first?.path ?? "")
      var selection = CalibrationMatcher.match(
        LightRef(set, in: inventory), masters: pool.masters, excluded: excluded,
        force: force)
      if let note = pool.note { selection.notes.append(note) }
      let suggestions = CalibrationRole.allCases.compactMap { role in
        selection.master(role).map {
          Suggestion(
            id: CalibrationMatcher.suggestionID(set.key, role: role), role: role, master: $0)
        }
      }
      return Channel(key: set.key, suggestions: suggestions, notes: selection.notes)
    }
  }

  /// The masters a run would match against (`PreviewCandidates`): the library plus a path-less
  /// master for every calibration set no library master already satisfies.
  package static func candidates(inventory: Inventory?, library: [CalibrationMaster])
    -> [CalibrationMaster]
  {
    guard let inventory else { return library }
    var out = library
    for type in MasterType.buildOrder {
      for set in inventory.sets where set.key.type == type.frameType {
        guard !library.contains(where: { Self.reused($0, for: set) }) else { continue }
        var master = synthetic(set)
        master.stampFilterSet(of: set.key, in: inventory)
        out.append(master)
      }
    }
    return out
  }

  /// Whether the run would reuse `master` for `set` (`MasterBuilder.reuse`): it stands for the
  /// set, was stacked with the default recipe, and its `.sig` proves the same frames.
  static func reused(_ master: CalibrationMaster, for set: FrameSet) -> Bool {
    master.recipe.isEmpty && master.satisfies(set.key)
      && PoolSignature.proves(master: master.path, builtFrom: set.frames.map(\.path))
  }

  /// The master a run would build from a calibration set, described before it exists.
  static func synthetic(_ set: FrameSet) -> CalibrationMaster {
    let type = MasterType(set.key.type) ?? .bias
    var master = CalibrationMaster(type: type, path: "")
    master.filter = set.key.filter
    master.exposureMs = set.key.exposureMs
    master.gain = set.key.gain
    master.offset = set.key.offset
    master.tempMilliC = set.key.tempBucketC * 1000
    master.hasTemp = type.isThermal
    master.bin = set.key.bin
    master.frameCount = set.count
    master.session = set.key.session
    return master
  }
}
