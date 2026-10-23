extension FrameSet {
  /// The id a clip-filter override is stored under: the set's id with its night.
  ///
  /// The night is added even when the scan did not split nights (`SetKey.session` empty), so the
  /// override still names this night once the project scans its folders together. A set without
  /// one common dated night keeps its id.
  package var overrideID: String {
    guard key.session.isEmpty, let night = frames.first?.session, !night.isEmpty,
      frames.allSatisfy({ $0.session == night })
    else { return key.id }
    var dated = key
    dated.session = night
    return dated.id
  }
}

/// Which light set each clip-filter override names, and why an override names none.
enum FilterSetOverrides {
  /// The verdict per light set id that `overrides` assert, and one warning per override left out.
  ///
  /// An override matches a set by its id or its `overrideID`. One recorded without its night
  /// (`|s:`, a folder imported alone before `overrideID`) applies to the one dated set it can
  /// only mean; two candidates or none leave it out, said (R2: never dropped in silence).
  static func resolve(_ overrides: [String: FilterSet], sets: [FrameSet])
    -> (verdicts: [String: FilterSet], warnings: [String])
  {
    let lights = sets.filter { $0.key.type == .light }
    var verdicts: [String: FilterSet] = [:]
    var warnings: [String] = []
    for (id, verdict) in overrides.sorted(by: { $0.key < $1.key }) where verdict.isKnown {
      let exact = lights.filter { $0.key.id == id || $0.overrideID == id }
      let matches =
        exact.isEmpty && id.hasSuffix("|s:") ? lights.filter { undatedID($0) == id } : exact
      if matches.isEmpty {
        warnings.append(
          "filter set override \(verdict.rawValue) for \(id) matches no light set in this scan "
            + "— ignored; mark the night again in the import")
      } else if exact.isEmpty && matches.count > 1 {
        let nights = matches.map(\.key.session).sorted().joined(separator: ", ")
        warnings.append(
          "filter set override \(verdict.rawValue) for \(id) could mean \(matches.count) nights "
            + "(\(nights)) — ignored; mark the right night again in the import")
      } else {
        for set in matches { verdicts[set.key.id] = verdict }
      }
    }
    return (verdicts, warnings)
  }

  /// The id of `set` with the night left out, as a single-night scan writes it.
  private static func undatedID(_ set: FrameSet) -> String {
    var key = set.key
    key.session = ""
    return key.id
  }
}
