package import Foundation
package import ImageKit

extension CaptureFrame {
  /// Reads the primary header of the FITS file at `url` (no pixels decoded) and builds the frame.
  package init(reading url: URL, timeZone: TimeZone) throws {
    try self.init(path: url.path, header: FITSFile.read(at: url).header, timeZone: timeZone)
  }

  /// The frame a header and a path describe (`FrameFromHeader`): header cards first, then the
  /// SharpCap sidecar and the file/folder names fill only what the header left blank.
  /// `timeZone` is the site's: it decides the observing night.
  package init(path: String, header: FITSHeader, timeZone: TimeZone) {
    self.init(path: path)
    let cards = LegacyCards(header: header)
    binX = 1
    binY = 1
    readAcquisition(cards)
    readSensor(cards)
    readOrigin(cards, timeZone: timeZone)
    if let value = cards.string("IMAGETYP") {
      let type = FrameClassifier.imageType(value)
      if type != .unknown {
        self.type = type
        classSource = .header
      }
    }
    backfillFromPath()
  }

  private mutating func readAcquisition(_ cards: LegacyCards) {
    if let value = cards.string("FILTER") { filter = Filter.normalize(value) }
    if let seconds = cards.exposureSeconds { exposureMs = Int((seconds * 1000).rounded()) }
    if let gain = cards.int("GAIN") {
      self.gain = gain
      hasGain = true
    }
    if let offset = cards.int("OFFSET") { self.offset = offset }
    if let eGain = cards.double("EGAIN"), eGain > 0 { self.eGain = eGain }
    if let celsius = cards.double("CCD-TEMP") {
      tempMilliC = Int((celsius * 1000).rounded())
      hasTemp = true
    }
    if let bin = cards.int("XBINNING"), bin > 0 {
      binX = bin
      binY = bin
    }
    if let bin = cards.int("YBINNING"), bin > 0 { binY = bin }
  }

  private mutating func readSensor(_ cards: LegacyCards) {
    if let pattern = cards.string("BAYERPAT"), !pattern.isEmpty,
      pattern.caseInsensitiveCompare("NONE") != .orderedSame
    {
      bayer = pattern.uppercased()
    }
    width = cards.int("NAXIS1") ?? 0
    height = cards.int("NAXIS2") ?? 0
    // NAXIS3 = 3 is an already-debayered colour image (Siril writes these after -debayer).
    if let planes = cards.int("NAXIS3"), planes > 0 { channels = planes }
    instrument = cards.string("INSTRUME") ?? ""
    creator = cards.string("SWCREATE") ?? ""
    telescope = cards.string("TELESCOP") ?? ""
    if let focal = cards.double("FOCALLEN") { focalLengthMM = focal }
    if let pixel = cards.double("XPIXSZ") { pixelSizeUm = pixel }
  }

  private mutating func readOrigin(_ cards: LegacyCards, timeZone: TimeZone) {
    object = cards.string("OBJECT") ?? ""
    objectRA = cards.string("OBJCTRA") ?? ""
    objectDec = cards.string("OBJCTDEC") ?? ""
    if let date = cards.string("DATE-OBS") {
      dateObs = date
      dateObsMs = Self.parseDateObs(date)
      session = Night.key(ms: dateObsMs, in: timeZone)
    }
  }
}

/// Header cards read the way the legacy `fits.Header` accessors read them: values trimmed, `D`
/// exponents accepted, integers falling back to a truncated float.
struct LegacyCards {
  let header: FITSHeader

  func string(_ key: String) -> String? {
    header.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func double(_ key: String) -> Double? {
    string(key).flatMap { Double($0.replacingOccurrences(of: "D", with: "E", options: .caseInsensitive)) }
  }

  func int(_ key: String) -> Int? {
    guard let text = string(key) else { return nil }
    if let value = Int(text) { return value }
    guard let value = double(key), value.isFinite, abs(value) < 9.2e18 else { return nil }
    return Int(value)
  }

  /// EXPTIME, else EXPOSURE, else ASICAP's EXPOINUS in microseconds.
  var exposureSeconds: Double? {
    double("EXPTIME") ?? double("EXPOSURE") ?? double("EXPOINUS").map { $0 / 1e6 }
  }
}
