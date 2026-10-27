internal import FilterKit

extension FrameSet {
  /// The id a clip-filter override is stored under: the set's id with its night.
  ///
  /// The night is added even when the scan did not split nights (`SetKey.session` empty), so the
  /// override still names this night once the project scans its folders together. The night is
  /// that of the set's dated frames (an undated stray does not hide it); a set whose dated
  /// frames span several nights, or none, keeps its id.
  package var overrideID: String {
    let nights = Set(frames.map(\.session).filter { !$0.isEmpty })
    guard key.session.isEmpty, nights.count == 1, let night = nights.first else { return key.id }
    var dated = key
    dated.session = night
    return dated.id
  }
}

/// Which light set each clip-filter override names, and why an override names none.
enum FilterSetOverrides {
  /// The verdict per light set id that `overrides` assert, and one warning per override that
  /// was left out or had to guess its night.
  ///
  /// An override matches a set by its id or its `overrideID`. One recorded without its night
  /// (`|s:`, a folder imported alone before `overrideID`) applies to the one dated set it can
  /// only mean, said; a set another override names exactly is not a candidate (the dated choice
  /// supersedes the undated one). Two candidates or none leave it out, said (R2).
  static func resolve(_ overrides: [String: FilterSet], sets: [FrameSet])
    -> (verdicts: [String: FilterSet], warnings: [String])
  {
    let lights = sets.filter { $0.key.type == .light }
    var exactSets: [String: [String]] = [:]
    var undatedSets: [String: [FrameSet]] = [:]
    for set in lights {
      for id in Set([set.key.id, set.overrideID]) { exactSets[id, default: []].append(set.key.id) }
      undatedSets[undatedID(set), default: []].append(set)
    }
    let named = Set(
      overrides.keys.filter { overrides[$0]?.isKnown == true }.flatMap {
        exactSets[$0] ?? []
      })
    var verdicts: [String: FilterSet] = [:]
    var warnings: [String] = []
    for (id, verdict) in overrides.sorted(by: { $0.key < $1.key }) where verdict.isKnown {
      if let exact = exactSets[id] {
        for setID in exact { verdicts[setID] = verdict }
        continue
      }
      let all = id.hasSuffix("|s:") ? undatedSets[id] ?? [] : []
      let candidates = all.filter { !named.contains($0.key.id) }
      switch candidates.count {
      case 1:
        verdicts[candidates[0].key.id] = verdict
        warnings.append(
          "filter set override \(verdict.rawValue) for \(id) was recorded without its night — "
            + "applied to \(candidates[0].key.session), the only night it can mean")
      case 0 where !all.isEmpty:
        break  // Every night it could mean carries a dated override of its own.
      case 0:
        warnings.append(
          "filter set override \(verdict.rawValue) for \(id) matches no light set in this scan "
            + "— ignored")
      default:
        let nights = candidates.map(\.key.session).sorted().joined(separator: ", ")
        warnings.append(
          "filter set override \(verdict.rawValue) for \(id) could mean \(candidates.count) "
            + "nights (\(nights)) — ignored; mark the right night again in the import")
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
