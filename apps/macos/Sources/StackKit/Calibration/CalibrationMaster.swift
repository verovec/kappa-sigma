package import FilterKit

/// A built or library master calibration frame (`calib.Master`).
package struct CalibrationMaster: Codable, Equatable, Sendable {
  package var type: MasterType
  /// Flats only: the filter the flat set was shot through (`""` for a shared or colour flat).
  package var filter = ""
  package var exposureMs = 0
  package var gain = 0
  package var offset = 0
  package var tempMilliC = 0
  package var hasTemp = false
  package var bin = 0
  package var frameCount = 0
  /// The `.fits` file; `""` for a master a run would build (a preview candidate).
  package var path: String
  /// The clip filter of a one-shot-colour FLAT, inherited from its night; never on darks/bias.
  package var filterSet = FilterSet.unknown
  /// The capture night of a per-night flat (`""` = night-blind).
  package var session = ""
  /// Came from the shared library rather than this run's own frames (named in a note).
  package var fromLibrary = false
  /// Fingerprint of a non-default stacking recipe, part of the file name; `""` for the default.
  package var recipe = ""

  /// A master of `type` at `path`, every other field zero.
  package init(type: MasterType, path: String) {
    self.type = type
    self.path = path
  }

  /// Darks are matched within this many °C of a light's temperature.
  package static let temperatureToleranceC = 5.0

  /// Whether this master can stand for a calibration set (`masterMatchesSet`): same type, camera,
  /// filter and night; same exposure except for bias; darks within ±5 °C.
  ///
  /// A per-night flat set is never satisfied by a night-blind master (dust may have moved).
  package func satisfies(_ key: SetKey) -> Bool {
    guard MasterType(key.type) == type, gain == key.gain, offset == key.offset, bin == key.bin,
      filter == key.filter, session == key.session
    else { return false }
    if type != .bias && exposureMs != key.exposureMs { return false }
    if type.isThermal && temperatureDeltaC(to: key) > Self.temperatureToleranceC { return false }
    return true
  }

  /// |master − light| in °C, the light at its cluster's whole-degree temperature.
  func temperatureDeltaC(to light: SetKey) -> Double {
    abs(Double(tempMilliC - light.tempBucketC * 1000)) / 1000
  }

  /// Same gain, offset and bin as the light.
  func sameCamera(as light: SetKey) -> Bool {
    gain == light.gain && offset == light.offset && bin == light.bin
  }

  /// Gives a FLAT the clip filter of the night it was shot on (`stampFlatFilterSet`): a flat has no
  /// sky to classify, so it inherits its night's lights.
  ///
  /// Darks and bias are closed-shutter.
  package mutating func stampFilterSet(of key: SetKey, in inventory: Inventory?) {
    guard type == .flat, let inventory else { return }
    let night = inventory.nightFilterSet(key.session)
    if night.isKnown { filterSet = night }
  }
}
