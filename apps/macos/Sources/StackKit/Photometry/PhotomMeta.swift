internal import Foundation

/// The capture parameters behind the exposure/gain prior (`photom.Meta`); the zero value disables
/// it.
package struct PhotomMeta: Equatable, Sendable {
  package var exposureMs = 0
  package var gain = 0
  /// A real gain (0 included), not the zero value of a frame without one.
  package var gainKnown = false
  package var instrument = ""
  /// The capture software (SWCREATE): old ASICAP writes no INSTRUME card.
  package var creator = ""

  /// Capture parameters.
  package init(
    exposureMs: Int = 0, gain: Int = 0, gainKnown: Bool = false, instrument: String = "",
    creator: String = ""
  ) {
    self.exposureMs = exposureMs
    self.gain = gain
    self.gainKnown = gainKnown
    self.instrument = instrument
    self.creator = creator
  }

  /// The ZWO 0.1 dB gain law applies: a ZWO/ASI instrument, or ASICAP as the capture software.
  var zwoGainLaw: Bool {
    let name = instrument.trimmingCharacters(in: .whitespaces).uppercased()
    if name.hasPrefix("ZWO") || name.hasPrefix("ASI") { return true }
    return creator.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("ASICAP")
  }

  /// The predicted flux ratio reference/frame (`metaExpectedScale`): the exposure ratio, times the
  /// gain factor when both sides confirm the ZWO law; equal known gains cancel; otherwise 0 (no
  /// honest prediction).
  static func expectedScale(frame: Self, reference: Self) -> Double {
    guard frame.exposureMs > 0, reference.exposureMs > 0 else { return 0 }
    var expected = Double(reference.exposureMs) / Double(frame.exposureMs)
    let known = frame.gainKnown && reference.gainKnown
    if known && frame.zwoGainLaw && reference.zwoGainLaw {
      expected *= linearGain(reference.gain) / linearGain(frame.gain)
    } else if !(known && frame.gain == reference.gain) {
      return 0
    }
    return expected > 0 && expected.isFinite ? expected : 0
  }

  /// A ZWO gain (0.1 dB units) as a flux multiplier: 10^(g/200).
  static func linearGain(_ gain: Int) -> Double { pow(10, Double(gain) / 200) }
}
