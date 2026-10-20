import Foundation
import StackKit

/// An `Inventory` in the shape the legacy engine serialized it (`inventory.json` of an oracle
/// case): Go field names, `omitempty` fields dropped when zero, `date_obs_ms` dropped like the
/// recorder's volatile keys, paths normalized by `normalize`.
enum InventoryJSON {
  typealias Object = [String: Any]

  static func object(_ inventory: Inventory, normalize: (String) -> String) -> Object {
    var out: Object = [
      "root": normalize(inventory.root),
      "frames": inventory.frames.map { frame($0, normalize: normalize) },
      "sets": inventory.sets.map(set),
      "videos": NSNull(),
      "warnings": inventory.warnings.isEmpty ? NSNull() : inventory.warnings.map(normalize) as Any,
      "color_model": inventory.colorModel.rawValue,
    ]
    if !inventory.filterSets.isEmpty { out["filter_sets"] = inventory.filterSets.mapValues(\.rawValue) }
    if !inventory.sessions.isEmpty { out["sessions"] = inventory.sessions.map(session) }
    return out
  }

  static func frame(_ frame: CaptureFrame, normalize: (String) -> String) -> Object {
    var out: Object = [
      "path": normalize(frame.path), "type": frame.type.rawValue, "exposure_ms": frame.exposureMs,
      "gain": frame.gain, "offset": frame.offset, "temp_milli_c": frame.tempMilliC,
      "has_temp": frame.hasTemp, "bin_x": frame.binX, "bin_y": frame.binY, "width": frame.width,
      "height": frame.height, "class_source": frame.classSource.rawValue,
    ]
    let optional: [(String, Any, Bool)] = [
      ("filter", frame.filter, !frame.filter.isEmpty), ("has_gain", true, frame.hasGain),
      ("egain", frame.eGain, frame.eGain != 0), ("bayer", frame.bayer, !frame.bayer.isEmpty),
      ("channels", frame.channels, frame.channels != 0), ("object", frame.object, !frame.object.isEmpty),
      ("instrument", frame.instrument, !frame.instrument.isEmpty),
      ("creator", frame.creator, !frame.creator.isEmpty), ("telescope", frame.telescope, !frame.telescope.isEmpty),
      ("date_obs", frame.dateObs, !frame.dateObs.isEmpty), ("session", frame.session, !frame.session.isEmpty),
      ("wheel_slot", frame.wheelSlot, frame.wheelSlot != 0),
      ("filter_confidence", frame.filterConfidence, frame.filterConfidence != 0),
      ("wheel_transition", true, frame.wheelTransition),
      ("focal_len_mm", frame.focalLengthMM, frame.focalLengthMM != 0),
      ("pixel_size_um", frame.pixelSizeUm, frame.pixelSizeUm != 0),
      ("objctra", frame.objectRA, !frame.objectRA.isEmpty), ("objctdec", frame.objectDec, !frame.objectDec.isEmpty),
    ]
    for (key, value, present) in optional where present { out[key] = value }
    return out
  }

  static func set(_ set: FrameSet) -> Object {
    let key = set.key
    var keyObject: Object = [
      "type": key.type.rawValue, "exposure_ms": key.exposureMs, "gain": key.gain,
      "offset": key.offset, "temp_bucket_c": key.tempBucketC, "bin": key.bin,
    ]
    if !key.object.isEmpty { keyObject["object"] = key.object }
    if !key.filter.isEmpty { keyObject["filter"] = key.filter }
    if !key.session.isEmpty { keyObject["session"] = key.session }
    if key.color { keyObject["color"] = true }
    var out: Object = ["key": keyObject, "count": set.count, "total_integration_ms": set.totalIntegrationMs]
    if set.filterSet != .unknown { out["filter_set"] = set.filterSet.rawValue }
    return out
  }

  static func session(_ info: SessionInfo) -> Object {
    var out: Object = [
      "key": info.key,
      "counts": Dictionary(uniqueKeysWithValues: info.counts.map { ($0.key.rawValue, $0.value) }),
    ]
    if info.startMs != 0 { out["start_ms"] = info.startMs }
    if info.endMs != 0 { out["end_ms"] = info.endMs }
    if !info.configs.isEmpty {
      out["configs"] = info.configs.map { config -> Object in
        var item: Object = [
          "exposure_ms": config.exposureMs, "gain": config.gain, "offset": config.offset,
          "bin": config.bin, "temp_bucket_c": config.tempBucketC, "count": config.count,
        ]
        if !config.filter.isEmpty { item["filter"] = config.filter }
        return item
      }
    }
    return out
  }

  /// One value as sorted-key JSON, the unit of comparison.
  static func text(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject([value]),
      let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
    else { return "\(value)" }
    return String(decoding: data, as: UTF8.self)
  }

  /// Every difference between a recorded inventory and ours, as readable lines. Session configs
  /// are compared as a multiset: Go ordered ties on (filter, exposure, gain) by map iteration.
  static func differences(recorded: Object, actual: Object) -> [String] {
    var out: [String] = []
    for key in ["root", "color_model", "videos", "warnings", "filter_sets"]
    where text(recorded[key] ?? NSNull()) != text(actual[key] ?? NSNull()) {
      out.append("\(key): recorded \(text(recorded[key] ?? NSNull())) ≠ \(text(actual[key] ?? NSNull()))")
    }
    out += pairwise("frames", recorded["frames"], actual["frames"])
    out += pairwise("sets", recorded["sets"], actual["sets"])
    out += pairwise("sessions", sortedConfigs(recorded["sessions"]), sortedConfigs(actual["sessions"]))
    return out
  }

  private static func pairwise(_ name: String, _ recorded: Any?, _ actual: Any?) -> [String] {
    let left = recorded as? [Any] ?? []
    let right = actual as? [Any] ?? []
    var out = left.count == right.count ? [] : ["\(name): recorded \(left.count) ≠ \(right.count)"]
    for (index, pair) in zip(left, right).enumerated() where text(pair.0) != text(pair.1) {
      out.append("\(name)[\(index)]:\n  recorded \(text(pair.0))\n  actual   \(text(pair.1))")
    }
    return out
  }

  private static func sortedConfigs(_ sessions: Any?) -> Any? {
    (sessions as? [Object])?.map { session in
      var session = session
      if let configs = session["configs"] as? [Any] {
        session["configs"] = configs.sorted { text($0) < text($1) }
      }
      return session
    }
  }
}
