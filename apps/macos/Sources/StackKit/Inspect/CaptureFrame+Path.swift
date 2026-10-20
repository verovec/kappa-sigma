internal import Foundation

extension CaptureFrame {
  /// A FITS DATE-OBS as epoch milliseconds, UTC, 0 when unparseable (`parseDateObs`).
  ///
  /// The legacy layouts: `YYYY-MM-DD[T| ]hh:mm:ss[.fraction]` and a bare `YYYY-MM-DD`; any number of
  /// fraction digits, truncated to the millisecond like Go's `UnixMilli`.
  package static func parseDateObs(_ text: String) -> Int {
    let pattern = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?)?$/
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = trimmed.wholeMatch(of: pattern) else { return 0 }
    let out = match.output
    var parts = DateComponents()
    parts.year = Int(out.1)
    parts.month = Int(out.2)
    parts.day = Int(out.3)
    parts.hour = out.4.flatMap { Int($0) } ?? 0
    parts.minute = out.5.flatMap { Int($0) } ?? 0
    parts.second = out.6.flatMap { Int($0) } ?? 0
    guard Self.isValid(parts), let date = Self.utc.date(from: parts) else { return 0 }
    let fraction = out.7.map { String($0).padding(toLength: 3, withPad: "0", startingAt: 0) }
    let millis = fraction.flatMap { Int($0.prefix(3)) } ?? 0
    return Int(date.timeIntervalSince1970.rounded()) * 1000 + millis
  }

  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// Go's `time.Parse` refuses out-of-range fields where `Calendar` would roll them over.
  private static func isValid(_ parts: DateComponents) -> Bool {
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      (1...12).contains(month), day >= 1,
      let first = utc.date(from: DateComponents(year: year, month: month, day: 1)),
      let days = utc.range(of: .day, in: .month, for: first)
    else { return false }
    return days.contains(day) && (0...23).contains(parts.hour ?? 0)
      && (0...59).contains(parts.minute ?? 0) && (0...59).contains(parts.second ?? 0)
  }

  /// Fills what the header left blank from the SharpCap sidecar, then from the file and folder
  /// names (`backfillMeta`).
  ///
  /// Header values always win; no pixels are read.
  mutating func backfillFromPath() {
    let sidecar = SharpcapSidecar.read(beside: path)
    if let sidecar { apply(sidecar) }
    apply(PathMeta(path: path))
    // A flat's filter comes from the wheel alias once its folder settled the type: flats group
    // per filter, and flat names rarely carry a filter token.
    if let alias = sidecar?.slotAlias, !alias.isEmpty, type == .flat, filter.isEmpty {
      filter = alias
      filterConfidence = 1
    }
  }

  private mutating func apply(_ sidecar: SharpcapSidecar) {
    wheelSlot = sidecar.slot
    if exposureMs == 0, sidecar.exposureMs > 0 { exposureMs = sidecar.exposureMs }
    if gain == 0, sidecar.hasGain {
      gain = sidecar.gain
      hasGain = true
    }
    // ZWO "Brightness": without it, TIFF/headerless cal frames never match their lights' offset.
    if offset == 0, sidecar.hasOffset { offset = sidecar.offset }
    if !hasTemp, sidecar.hasTemp {
      tempMilliC = sidecar.tempMilliC
      hasTemp = true
    }
  }

  private mutating func apply(_ meta: PathMeta) {
    if filter.isEmpty { filter = meta.filter }
    if exposureMs == 0 { exposureMs = meta.exposureMs }
    if gain == 0 {
      gain = meta.gain
      // A name cannot express a real gain of 0.
      if meta.gain > 0 { hasGain = true }
    }
    if !hasTemp, meta.hasTemp {
      tempMilliC = meta.tempMilliC
      hasTemp = true
    }
    if binX <= 1, meta.bin > 0 {
      binX = meta.bin
      binY = meta.bin
    }
    if type == .unknown, meta.type != .unknown {
      type = meta.type
      classSource = .filename
    }
    if wheelSlot == 0 { wheelSlot = meta.wheelSlot }
  }
}
