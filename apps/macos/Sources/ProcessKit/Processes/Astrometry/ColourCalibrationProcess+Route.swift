package import ImageKit

/// The OSC or mono route of SPCC and the names still to choose (card 0140).
extension ColourCalibrationProcess {
  /// The routes, by `camera` value: a colour (OSC) camera, or a mono one.
  package static let cameras = ["osc", "mono"]
  /// The names SPCC needs from a colour (OSC) camera.
  package static let oscNames = ["sensor", "filter"]
  /// The names SPCC needs from a mono camera (`-monosensor=`, `-rfilter=`…).
  package static let monoNames = ["monoSensor", "rFilter", "gFilter", "bFilter"]
  /// The reason of the header's camera: the plate solve's header reason, one catalog key.
  package static let fromHeader = PlateSolveProcess.fromHeader
  package static let suggestionReasons = [fromHeader]

  /// True when `params` take the mono route (`camera`).
  package static func isMono(_ params: ParamSet) -> Bool {
    params.choice("camera") == "mono"
  }

  /// The names SPCC still needs on the route `params` show; none when unticked or for PCC.
  package static func unchosen(_ params: ParamSet) -> [String] {
    guard params.flag("enabled"), params.choice("method") == "spcc" else { return [] }
    return (isMono(params) ? monoNames : oscNames).filter { params.choice($0).isEmpty }
  }

  /// The camera the header's `INSTRUME` names (`SensorHint`): its route and its sensor, one
  /// offer with the instrument as subject; none for an unknown camera.
  package static func suggestions(header: FITSHeader?) -> [Suggestion] {
    guard let instrume = header?.string("INSTRUME"),
      let hint = SensorHint.suggest(instrume: instrume)
    else { return [] }
    return [
      ("camera", hint.mono ? "mono" : "osc"), (hint.mono ? "monoSensor" : "sensor", hint.sensor),
    ].map { id, value in
      Suggestion(paramID: id, value: .choice(value), reason: fromHeader, subject: instrume)
    }
  }
}
