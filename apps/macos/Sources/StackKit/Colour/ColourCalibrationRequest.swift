/// What a colour calibration is told (card 0094): the method the user chose and every value it
/// runs with, passed explicitly (SPCC otherwise reuses the last names it was given).
package struct ColourCalibrationRequest: Sendable {
  /// SPCC with its spectral data, or PCC.
  package enum Method: Equatable, Sendable {
    /// Spectrophotometric: the OSC sensor, its filter and the white reference, as Siril names
    /// them (`spcc_list`).
    case spcc(sensor: String, filter: String, whiteReference: String)
    /// Spectrophotometric on a mono camera's colour image (card 0140): the mono sensor, the red,
    /// green and blue filters it was shot through, and the white reference.
    case monoSPCC(
      sensor: String, red: String, green: String, blue: String, whiteReference: String)
    /// Photometric: star colours from the catalogue.
    case pcc

    /// The spectral names Siril must list before it runs, by `spcc_list` kind; none for PCC.
    package var names: [ColourCalibrationError.NameKind: String] {
      switch self {
      case .spcc(let sensor, let filter, let reference):
        [.sensor: sensor, .filter: filter, .whiteReference: reference]
      case .monoSPCC(let sensor, let red, let green, let blue, let reference):
        [
          .monoSensor: sensor, .redFilter: red, .greenFilter: green, .blueFilter: blue,
          .whiteReference: reference,
        ]
      case .pcc: [:]
      }
    }
  }

  /// SPCC or PCC.
  package var method: Method
  /// Faintest catalogue star used; `nil`: Siril's value for the field.
  package var limitMag: Double?
  /// Background reference outlier tolerance in σ, below and above the median, both as
  /// magnitudes (Siril's defaults 2.8 / 2.0; Siril 1.4.4 refuses a negative lower value).
  package var backgroundTolerance: (below: Double, above: Double)
  /// Local or online Gaia.
  package var catalogue: PlateSolveRequest.Catalogue

  /// A request of these values.
  package init(
    method: Method, limitMag: Double?, backgroundTolerance: (below: Double, above: Double),
    catalogue: PlateSolveRequest.Catalogue
  ) {
    self.method = method
    self.limitMag = limitMag
    self.backgroundTolerance = backgroundTolerance
    self.catalogue = catalogue
  }

  /// The command, every value written out.
  package var command: SirilCommand {
    var options: [String] = []
    if let limitMag { options.append("-limitmag=" + GoFormat.shortest(limitMag)) }
    options.append(
      "-bgtol=" + GoFormat.shortest(backgroundTolerance.below) + ","
        + GoFormat.shortest(backgroundTolerance.above))
    options.append("-catalog=" + catalogue.sirilName)
    switch method {
    case .spcc(let sensor, let filter, let reference):
      return .spcc(
        [
          "\"-oscsensor=\(sensor)\"", "\"-oscfilter=\(filter)\"", "\"-whiteref=\(reference)\"",
        ] + options)
    case .monoSPCC(let sensor, let red, let green, let blue, let reference):
      return .spcc(
        [
          "\"-monosensor=\(sensor)\"", "\"-rfilter=\(red)\"", "\"-gfilter=\(green)\"",
          "\"-bfilter=\(blue)\"", "\"-whiteref=\(reference)\"",
        ] + options)
    case .pcc:
      return .pcc(options)
    }
  }
}
