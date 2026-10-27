package import ImageKit

/// The OSC or mono route of SPCC and the names still to choose (card 0140).
extension ColourCalibrationProcess {
  /// The names SPCC needs on an OSC bundle.
  package static let oscNames = ["sensor", "filter"]
  /// The names SPCC needs on a mono bundle (`-monosensor=`, `-rfilter=`…).
  package static let monoNames = ["monoSensor", "rFilter", "gFilter", "bFilter"]
  /// The reason of the header's camera: an English key of the catalog.
  package static let fromHeader = "From the image header"
  package static let suggestionReasons = [fromHeader]

  /// True when the bundle of `layerIDs` comes from a mono camera: layers, none of them the OSC
  /// colour layer `RGB` (an OSC clip always has it; no layer known reads as OSC).
  package static func isMono(layerIDs: Set<String>) -> Bool {
    !layerIDs.isEmpty && !layerIDs.contains("RGB")
  }

  /// The names SPCC still needs on the route of `layerIDs`; none when unticked or for PCC.
  package static func unchosen(_ params: ParamSet, layerIDs: Set<String>) -> [String] {
    guard params.flag("enabled"), params.choice("method") == "spcc" else { return [] }
    let names = isMono(layerIDs: layerIDs) ? monoNames : oscNames
    return names.filter { params.choice($0).isEmpty }
  }

  /// The sensor the header's `INSTRUME` names (`SensorHint`), offered on the route's sensor
  /// with the instrument as its subject; none off the route or for an unknown camera.
  package static func suggestions(header: FITSHeader?, layerIDs: Set<String>) -> [Suggestion] {
    guard let instrume = header?.string("INSTRUME"),
      let hint = SensorHint.suggest(instrume: instrume),
      hint.mono == isMono(layerIDs: layerIDs)
    else { return [] }
    return [
      Suggestion(
        paramID: hint.mono ? "monoSensor" : "sensor", value: .choice(hint.sensor),
        reason: fromHeader, subject: instrume)
    ]
  }
}
