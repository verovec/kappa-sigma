import Foundation
import StackKit

/// Compares a plan (built masters + per-light selections) with a case's `calibration.json`:
/// the masters field by field, each light set's bias/dark/flat and `-opt`, its matcher notes as a
/// prefix of the recorded notes (later pipeline stages append theirs), and each recorded
/// per-night group of a multi-night case.
enum CalibrationPlanOracle {
  typealias Object = [String: Any]

  static func differences(
    recorded: Object, masters: [CalibrationMaster], inventory: Inventory
  ) -> [String] {
    var out = compareMasters(recorded["masters"] as? [Object] ?? [], masters)
    let lights = inventory.sets.filter { $0.key.type == .light }
    for channel in recorded["channels"] as? [Object] ?? [] {
      let filter = channel["filter"] as? String ?? ""
      let groups = channel["groups"] as? [Object] ?? []
      for group in groups {
        let session = group["session"] as? String ?? ""
        guard
          let set = lights.first(where: { $0.key.filter == filter && $0.key.session == session })
        else {
          out.append("no light set \(filter) \(session)")
          continue
        }
        let selection = select(set, inventory: inventory, masters: masters)
        for role in ["bias", "dark", "flat"]
        where (group[role] as? String ?? "") != name(selection, role) {
          out.append(
            "\(filter) \(session) \(role): recorded \(group[role] ?? "-") "
              + "≠ \(name(selection, role))"
          )
        }
      }
      let representative = groups.first?["session"] as? String ?? ""
      guard
        let set = lights.first(where: {
          $0.key.filter == filter && $0.key.session == representative
        }),
        let recordedSelection = channel["selection"] as? Object
      else {
        out.append("no light set for channel \(filter)")
        continue
      }
      out += compareSelection(
        recordedSelection, select(set, inventory: inventory, masters: masters), label: filter)
    }
    return out
  }

  /// What the run applies to one light set: the sensor-filtered pool, then the matcher.
  static func select(_ set: FrameSet, inventory: Inventory, masters: [CalibrationMaster])
    -> CalibrationSelection
  {
    let pool = DimensionGuard.keepMatching(masters, lightPath: set.frames.first?.path ?? "")
    var selection = CalibrationMatcher.match(LightRef(set, in: inventory), masters: pool.masters)
    if let note = pool.note { selection.notes.append(note) }
    return selection
  }

  private static func name(_ selection: CalibrationSelection, _ role: String) -> String {
    let master: CalibrationMaster? =
      switch role {
      case "bias": selection.bias
      case "dark": selection.dark
      default: selection.flat
      }
    return master.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? ""
  }

  private static func compareSelection(
    _ recorded: Object, _ ours: CalibrationSelection, label: String
  ) -> [String] {
    var out: [String] = []
    for role in ["bias", "dark", "flat"] {
      let theirs =
        ((recorded[role] as? Object)?["path"] as? String).map {
          URL(fileURLWithPath: $0).lastPathComponent
        } ?? ""
      if theirs != name(ours, role) {
        out.append("\(label) \(role): recorded \(theirs) ≠ \(name(ours, role))")
      }
    }
    if (recorded["dark_optimize"] as? Bool ?? false) != ours.darkOptimize {
      out.append("\(label) dark_optimize differs")
    }
    let notes = recorded["notes"] as? [String] ?? []
    if Array(notes.prefix(ours.notes.count)) != ours.notes {
      out.append("\(label) notes: recorded \(notes) does not start with \(ours.notes)")
    }
    return out
  }

  private static func compareMasters(_ recorded: [Object], _ ours: [CalibrationMaster]) -> [String]
  {
    var out =
      recorded.count == ours.count ? [] : ["masters: recorded \(recorded.count) ≠ \(ours.count)"]
    for (theirs, mine) in zip(recorded, ours) {
      let expected: [String: String] = [
        "type": theirs["type"] as? String ?? "", "filter": theirs["filter"] as? String ?? "",
        "exposure_ms": "\(theirs["exposure_ms"] ?? 0)", "gain": "\(theirs["gain"] ?? 0)",
        "offset": "\(theirs["offset"] ?? 0)", "bin": "\(theirs["bin"] ?? 0)",
        "temp_milli_c": "\(theirs["temp_milli_c"] ?? 0)",
        "has_temp": "\(theirs["has_temp"] as? Bool ?? false)",
        "frame_count": "\(theirs["frame_count"] ?? 0)",
        "session": theirs["session"] as? String ?? "",
        "filter_set": theirs["filter_set"] as? String ?? "unknown",
        "name": URL(fileURLWithPath: theirs["path"] as? String ?? "").lastPathComponent,
      ]
      let actual: [String: String] = [
        "type": mine.type.rawValue, "filter": mine.filter, "exposure_ms": "\(mine.exposureMs)",
        "gain": "\(mine.gain)", "offset": "\(mine.offset)", "bin": "\(mine.bin)",
        "temp_milli_c": "\(mine.tempMilliC)", "has_temp": "\(mine.hasTemp)",
        "frame_count": "\(mine.frameCount)",
        "session": mine.session, "filter_set": mine.filterSet.rawValue,
        "name": URL(fileURLWithPath: mine.path).lastPathComponent,
      ]
      for key in expected.keys.sorted() where expected[key] != actual[key] {
        out.append(
          "master \(expected["name"] ?? "") \(key): recorded \(expected[key] ?? "") "
            + "≠ \(actual[key] ?? "")"
        )
      }
    }
    return out
  }
}
