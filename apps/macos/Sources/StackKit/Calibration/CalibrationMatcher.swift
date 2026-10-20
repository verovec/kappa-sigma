internal import Foundation

/// Picks the dark, flat and bias for a light set (`calib/match.go`), rule by rule.
///
/// - dark: same camera (gain/offset/bin) and exposure, nearest temperature within ±5 °C; else a
///   same-camera dark of another exposure scaled with `-opt` when a bias exists;
/// - flat: the light's filter, else any flat (shared dust), ranked by night then camera then depth,
///   never through another clip filter when both filter sets are known;
/// - bias: same camera.
///
/// `force` (the user's override) drops the camera, temperature and filter-set gates and applies
/// whatever exists, saying so. Every gap and fallback is a note, never a failure.
package enum CalibrationMatcher {
  /// The selection for `light` among `masters`, minus the roles the user excluded (by
  /// `suggestionID`).
  package static func match(
    _ light: LightRef, masters: [CalibrationMaster], excluded: [String] = [], force: Bool = false
  ) -> CalibrationSelection {
    drop(excluded, from: select(light, masters: masters, force: force), light: light.key)
  }

  /// The stable id of a (light set, role) suggestion — shared by the preview and the run.
  package static func suggestionID(_ light: SetKey, role: CalibrationRole) -> String {
    "\(role.rawValue)|\(light.filter)|g\(light.gain)o\(light.offset)b\(light.bin)"
      + "|e\(light.exposureMs)|t\(light.tempBucketC)"
  }

  private static func select(
    _ ref: LightRef, masters all: [CalibrationMaster], force: Bool
  ) -> CalibrationSelection {
    let light = ref.key
    let (masters, crossSet) = keepSameFilterSet(ref, all, force: force)
    var selection = CalibrationSelection()
    selection.bias = bestBias(light, masters, force: force)
    chooseDark(light, masters, force: force, into: &selection)
    if force {
      selection.notes += [
        forcedNote(light, selection.dark, .dark), forcedNote(light, selection.bias, .bias),
      ]
      .compactMap { $0 }
    }
    chooseFlat(ref, masters, force: force, into: &selection)
    // Name both sets when refusing the other set's flats COST something; silent otherwise.
    if crossSet > 0 && (selection.flat == nil || selection.flat?.session != light.session) {
      selection.notes.append(
        "\(crossSet) flat(s) excluded — these are \(ref.filterSet.rawValue) lights and those flats "
          + "are \(opposite(ref.filterSet).rawValue); shoot flats per filter set")
    }
    if selection.bias == nil && selection.dark == nil {
      selection.notes.append("no bias or dark — no read-noise calibration available")
    }
    if let note = borrowedNote(selection) { selection.notes.append(note) }
    return selection
  }

  private static func chooseDark(
    _ light: SetKey, _ masters: [CalibrationMaster], force: Bool,
    into selection: inout CalibrationSelection
  ) {
    if let dark = bestDark(light, masters, force: force) {
      selection.dark = dark
    } else if let dark = bestScalableDark(light, masters, force: force), selection.bias != nil {
      selection.dark = dark
      selection.darkOptimize = true
      selection.notes.append(
        "no \(light.exposureMs)ms dark — dark-optimized from the \(dark.exposureMs)ms master "
          + "(thermal signal bias-scaled)")
    } else if force, let dark = closestDark(light, masters) {
      // Forced last resort: no scaling possible, the closest dark is subtracted as is.
      selection.dark = dark
      selection.notes.append(
        "forced dark — the \(dark.exposureMs)ms master is applied to \(light.exposureMs)ms lights "
          + "without scaling (thermal signal may be over- or under-subtracted)")
    } else {
      selection.notes.append("no matching dark — dark calibration skipped")
    }
  }

  private static func chooseFlat(
    _ ref: LightRef, _ masters: [CalibrationMaster], force: Bool,
    into selection: inout CalibrationSelection
  ) {
    let light = ref.key
    guard let flat = bestFlat(light, masters) else {
      selection.notes.append("no flat available — flat correction skipped")
      return
    }
    selection.flat = flat
    if flat.filter != light.filter {
      let label = flat.filter.isEmpty ? "session" : flat.filter
      selection.notes.append(
        "no \(light.filter) flat — using the \(label) flat (corrects shared dust/vignetting)")
    }
    if !light.session.isEmpty && !flat.session.isEmpty && flat.session != light.session {
      selection.notes.append(
        "no \(light.session) flat — using the night \(flat.session) flat "
          + "(dust may have moved between nights)")
    }
    if force && ref.filterSet.isKnown && flat.filterSet.isKnown && ref.filterSet != flat.filterSet {
      selection.notes.append(
        "forced flat — these are \(ref.filterSet.rawValue) lights calibrated with a "
          + "\(flat.filterSet.rawValue) flat (wrong illumination profile)")
    }
  }

  /// Drops the flats shot through another clip filter (both sides known), BEFORE ranking, so the
  /// next-best candidate can still be found (`keepSameFilterSet`).
  private static func keepSameFilterSet(
    _ ref: LightRef, _ masters: [CalibrationMaster], force: Bool
  ) -> ([CalibrationMaster], Int) {
    guard !force, ref.filterSet.isKnown else { return (masters, 0) }
    let kept = masters.filter {
      !($0.type == .flat && $0.filterSet.isKnown && $0.filterSet != ref.filterSet)
    }
    return (kept, masters.count - kept.count)
  }

  private static func opposite(_ set: FilterSet) -> FilterSet {
    set == .dualband ? .broadband : .dualband
  }

  /// Names the masters that did not come from this run's own frames (`borrowedNote`).
  private static func borrowedNote(_ selection: CalibrationSelection) -> String? {
    let borrowed = CalibrationRole.allCases.compactMap { role -> String? in
      guard let master = selection.master(role), master.fromLibrary else { return nil }
      return "\(role.rawValue) \(PathMeta.baseName(master.path)) (\(master.frameCount) frames)"
    }
    guard !borrowed.isEmpty else { return nil }
    return "from the calibration library, not this session's own frames: "
      + borrowed.joined(separator: " · ")
  }

  /// Why a forced master differs from the light; `nil` when it does not.
  private static func forcedNote(
    _ light: SetKey, _ master: CalibrationMaster?, _ role: CalibrationRole
  ) -> String? {
    guard let master else { return nil }
    var differences: [String] = []
    if !master.sameCamera(as: light) {
      differences.append(
        "gain \(master.gain)/offset \(master.offset)/bin \(master.bin) "
          + "(yours: \(light.gain)/\(light.offset)/\(light.bin))")
    }
    if role == .dark && master.hasTemp
      && master.temperatureDeltaC(to: light) > CalibrationMaster.temperatureToleranceC
    {
      let celsius = String(format: "%+.0f", Double(master.tempMilliC) / 1000)
      let yours = light.tempBucketC >= 0 ? "+\(light.tempBucketC)" : "\(light.tempBucketC)"
      differences.append("\(celsius)°C (yours: ~\(yours)°C)")
    }
    guard !differences.isEmpty else { return nil }
    return
      "forced \(role.rawValue) — applied despite mismatched \(differences.joined(separator: ", "))"
  }

  /// Removes the roles the user unchecked for this light set (`dropExcluded`).
  private static func drop(_ excluded: [String], from input: CalibrationSelection, light: SetKey)
    -> CalibrationSelection
  {
    guard !excluded.isEmpty else { return input }
    let skip = Set(excluded)
    var selection = input
    if selection.dark != nil && skip.contains(suggestionID(light, role: .dark)) {
      selection.dark = nil
      selection.darkOptimize = false
      selection.notes.append("dark excluded — skipped on your request")
    }
    if selection.flat != nil && skip.contains(suggestionID(light, role: .flat)) {
      selection.flat = nil
      selection.notes.append("flat excluded — skipped on your request")
    }
    if selection.bias != nil && skip.contains(suggestionID(light, role: .bias)) {
      selection.bias = nil
      // -opt needs the bias to isolate the thermal signal.
      selection.darkOptimize = false
      selection.notes.append("bias excluded — skipped on your request")
    }
    return selection
  }
}
