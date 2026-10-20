/// Naming frames from their physical filter-wheel slot (`internal/inspect/wheelslot.go`): the
/// slot (sidecar or file name) is ground truth for mono captures without a FILTER card, and a
/// legend — `info.txt`, else the canonical wheel order — turns it into a filter name.
package enum WheelSlots {
  /// The conventional wheel order when nothing names the slots: every canonical filter, so a
  /// 7-slot wheel's narrowband positions resolve instead of becoming placeholders.
  package static let defaultLegend = Filter.allCases.map(\.rawValue)

  /// The filter of a 1-based slot, or a stable `S<n>` placeholder past the legend.
  package static func filter(slot: Int, legend: [String]) -> String {
    slot >= 1 && slot <= legend.count ? legend[slot - 1] : "S\(slot)"
  }

  /// Names the frames of a manifest's folders from their slots, learning slot → filter by pairing
  /// each chronological folder with the manifest token at the same position (capture order is not
  /// slot order).
  ///
  /// Returns `false` when no frame carries a slot.
  static func assign(
    _ manifest: CaptureManifest, folders: [String], byFolder: [String: [Int]],
    to inventory: inout Inventory
  ) -> Bool {
    let indices = folders.flatMap { byFolder[$0] ?? [] }
    guard indices.contains(where: { inventory.frames[$0].wheelSlot > 0 }) else { return false }
    var names = learnedNames(manifest, folders: folders, byFolder: byFolder, inventory: &inventory)
    if names.isEmpty {
      names = Dictionary(
        uniqueKeysWithValues: defaultLegend.enumerated().map { ($0.offset + 1, $0.element) })
    }
    var gains: [String: Int] = [:]
    var exposures: [String: Int] = [:]
    for slot in manifest.slots where !slot.filter.isEmpty {
      if slot.hasGain { gains[slot.filter] = slot.gain }
      if slot.exposureMs > 0 { exposures[slot.filter] = slot.exposureMs }
    }
    for index in indices {
      name(&inventory.frames[index]) { names[$0] ?? "S\($0)" }
      let frame = inventory.frames[index]
      guard !frame.type.isCalibration else { continue }
      if frame.gain == 0, let gain = gains[frame.filter] {
        inventory.frames[index].gain = gain
        inventory.frames[index].hasGain = true
      }
      if frame.exposureMs == 0, let exposure = exposures[frame.filter] {
        inventory.frames[index].exposureMs = exposure
      }
      manifest.fillTemperature(&inventory.frames[index])
    }
    return true
  }

  /// Folder i's physical slot holds the manifest's i-th filter; a clash is warned, last wins.
  private static func learnedNames(
    _ manifest: CaptureManifest, folders: [String], byFolder: [String: [Int]],
    inventory: inout Inventory
  ) -> [Int: String] {
    var names: [Int: String] = [:]
    for (slot, folder) in zip(manifest.slots, folders) where !slot.filter.isEmpty {
      let frames = inventory.frames
      let physical = (byFolder[folder] ?? []).map { frames[$0].wheelSlot }.first { $0 > 0 } ?? 0
      guard physical > 0 else { continue }
      if let previous = names[physical], previous != slot.filter {
        inventory.warnings.append(
          "filter-wheel slot \(physical) maps to both \"\(previous)\" and \"\(slot.filter)\" in "
            + "the info.txt legend — using \"\(slot.filter)\"")
      }
      names[physical] = slot.filter
    }
    if manifest.slots.count != folders.count {
      let paired = min(manifest.slots.count, folders.count)
      inventory.warnings.append(
        "info.txt lists \(manifest.slots.count) filter slots but there are \(folders.count) "
          + "capture folders — paired the first \(paired) in capture order")
    }
    return names
  }

  /// Names every still-unnamed light or flat that carries a slot, by the default wheel order —
  /// sibling capture folders with no `info.txt`.
  static func nameRemaining(_ inventory: inout Inventory) {
    for index in inventory.frames.indices {
      name(&inventory.frames[index]) { filter(slot: $0, legend: defaultLegend) }
    }
  }

  /// Fills an unnamed light/flat filter from its slot; an unknown type becomes a light.
  private static func name(_ frame: inout CaptureFrame, by filterOf: (Int) -> String) {
    guard frame.filter.isEmpty, frame.wheelSlot > 0, !frame.type.isFilterAgnostic else { return }
    frame.filter = filterOf(frame.wheelSlot)
    frame.classSource = .wheel
    frame.filterConfidence = 1
    if frame.type == .unknown { frame.type = .light }
  }

  /// One warning per slot that had no legend entry and was labeled `S<n>`.
  static func warnUnnamed(_ inventory: inout Inventory) {
    var seen: Set<String> = []
    for frame in inventory.frames
    where frame.classSource == .wheel && frame.filter.wholeMatch(of: /S\d+/) != nil
      && seen.insert(frame.filter).inserted
    {
      inventory.warnings.append(
        "filter-wheel slot \(frame.filter.dropFirst()) has no name legend — labeled "
          + "\"\(frame.filter)\"; map it to a channel in the UI")
    }
  }
}
