/// Why a colour calibration did not run, in words the user can act on.
package enum ColourCalibrationError: Error, Equatable, Sendable {
  /// What an SPCC name names, by its `spcc_list` kind.
  package enum NameKind: String, CaseIterable, Sendable {
    case sensor = "oscsensor"
    case filter = "oscfilter"
    case monoSensor = "monosensor"
    case redFilter = "redfilter"
    case greenFilter = "greenfilter"
    case blueFilter = "bluefilter"
    case whiteReference = "whiteref"
  }

  /// The image carries no plate solution: solve it first (plate solving).
  case unsolved
  /// A sensor, filter or white reference Siril does not list (it would quietly use another).
  case unknownName(kind: NameKind, name: String)
  /// The local Gaia catalogue is not there (`just download-catalogues`); nothing went online.
  case catalogueMissing(path: String)
  /// Siril found no calibration: its own reason (no other method is tried).
  case failed(reason: String)
  /// Siril reported success but wrote no calibrated image.
  case noOutput(path: String)
  /// Siril wrote an image but printed no white-balance factors to show (R2: nothing unshown).
  case noFactors
}
