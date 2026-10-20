/// The master file-name grammar (`masterName`), the library's key and its index's truth:
/// `master_<TYPE>[_<filter>][_<exp>ms]_g<gain>o<offset>_b<bin>[_<temp>C][_n<night>][_s<recipe>]`.
///
/// The default stacking recipe adds nothing, so every library master keeps its legacy name.
package enum MasterName {
  /// The file name (without `.fits`) of the master built from a calibration set.
  package static func make(_ key: SetKey, recipe: String = "") -> String {
    guard let type = MasterType(key.type) else { return "" }
    var name = "master_\(type.rawValue)"
    if !key.filter.isEmpty { name += "_\(key.filter)" }
    if type != .bias { name += "_\(key.exposureMs)ms" }
    name += "_g\(key.gain)o\(key.offset)_b\(key.bin)"
    if type != .bias { name += "_\(key.tempBucketC)C" }
    // Per-night flat sets: one file per night, or two nights' stacks overwrite each other.
    if !key.session.isEmpty { name += "_n\(key.session)" }
    if !recipe.isEmpty { name += "_s\(recipe)" }
    return name
  }

  /// The master a library file describes, or `nil` when the name is not a master's. The
  /// temperature is the set's whole-degree bucket (the file name is all the folder records).
  package static func parse(_ path: String) -> CalibrationMaster? {
    let file = PathMeta.baseName(path)
    guard file.hasSuffix(".fits"),
      let match = String(file.dropLast(5)).wholeMatch(
        of:
          /master_(BIAS|DARKFLAT|DARK|FLAT)(?:_([A-Za-z][A-Za-z0-9]*))?(?:_(\d+)ms)?_g(\d+)o(\d+)_b(\d+)(?:_(-?\d+)C)?(?:_n(\d{4}-\d{2}-\d{2}))?(?:_s([0-9a-f]+))?/),
      let type = MasterType(rawValue: String(match.1)),
      let gain = Int(match.4), let offset = Int(match.5), let bin = Int(match.6)
    else { return nil }
    var master = CalibrationMaster(type: type, path: path)
    master.filter = match.2.map(String.init) ?? ""
    master.exposureMs = match.3.flatMap { Int($0) } ?? 0
    master.gain = gain
    master.offset = offset
    master.bin = bin
    if let celsius = match.7.flatMap({ Int($0) }) {
      master.tempMilliC = celsius * 1000
      master.hasTemp = true
    }
    master.session = match.8.map(String.init) ?? ""
    master.recipe = match.9.map(String.init) ?? ""
    return master
  }
}
