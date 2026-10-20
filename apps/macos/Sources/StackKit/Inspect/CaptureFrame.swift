/// One capture file and the metadata inspect extracted from it (`inspect.Frame`).
///
/// Fields keep the legacy units and zero values: `0` / `""` mean "absent", with `hasGain` and
/// `hasTemp` separating a real 0 from a missing card. Phone/DSLR fields (ISO, pointing) are not
/// ported: deep-sky FITS only.
package struct CaptureFrame: Equatable, Sendable {
  /// Absolute path of the file.
  package var path: String
  package var type: FrameType = .unknown
  /// Canonical filter token, a custom name verbatim, `RGB` for colour, or `""`.
  package var filter = ""
  package var exposureMs = 0
  package var gain = 0
  /// A GAIN value exists somewhere (header, sidecar, name, manifest), even if it is 0.
  package var hasGain = false
  package var offset = 0
  /// Electrons per ADU (`EGAIN`); 0 when the header has none — never a guess.
  package var eGain = 0.0
  package var tempMilliC = 0
  package var hasTemp = false
  package var binX = 0
  package var binY = 0
  package var width = 0
  package var height = 0
  /// CFA pattern (`RGGB`…) of a one-plane colour mosaic; `""` for mono.
  package var bayer = ""
  /// Planes in the data unit (3 = already debayered); 0 means not determined.
  package var channels = 0
  package var object = ""
  package var instrument = ""
  /// Capture software (`SWCREATE`); old ASICAP writes no INSTRUME.
  package var creator = ""
  package var telescope = ""
  package var dateObs = ""
  package var dateObsMs = 0
  /// Observing-night key (`YYYY-MM-DD`, local noon bucket), `""` when undated.
  package var session = ""
  package var classSource: ClassSource = .none
  /// Physical filter-wheel position, 1-based; 0 = unknown.
  package var wheelSlot = 0
  package var filterConfidence = 0.0
  /// The first frame of a run whose brightness shows the wheel was still moving.
  package var wheelTransition = false
  package var focalLengthMM = 0.0
  package var pixelSizeUm = 0.0
  package var objectRA = ""
  package var objectDec = ""

  /// A frame with only a path: every field at its zero value.
  package init(path: String) {
    self.path = path
  }

  /// Carries all three primaries: a CFA mosaic or three planes.
  package var isColor: Bool { !bayer.isEmpty || channels >= 3 }

  /// Still a raw CFA mosaic, so calibration runs CFA-aware and debayers afterwards.
  package var needsDebayer: Bool { !bayer.isEmpty && channels < 3 }

  /// Sensor temperature in °C (meaningful only when `hasTemp`).
  package var tempC: Double { Double(tempMilliC) / 1000 }
}
