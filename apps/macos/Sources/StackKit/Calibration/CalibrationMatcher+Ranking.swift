internal import Foundation

extension CalibrationMatcher {
  /// The exposure-matched dark nearest in temperature (ties: the deeper stack).
  static func bestDark(_ light: SetKey, _ masters: [CalibrationMaster], force: Bool) -> CalibrationMaster? {
    var best: CalibrationMaster?
    var bestDelta = Double.greatestFiniteMagnitude
    for master in masters where master.type == .dark && master.exposureMs == light.exposureMs {
      if !force && !master.sameCamera(as: light) { continue }
      let delta = master.temperatureDeltaC(to: light)
      if !force && delta > CalibrationMaster.temperatureToleranceC { continue }
      if let current = best, !(delta < bestDelta || (delta == bestDelta && master.frameCount > current.frameCount)) {
        continue
      }
      best = master
      bestDelta = delta
    }
    return best
  }

  /// A same-camera dark of ANOTHER exposure for `-opt`: nearest temperature, then the longest
  /// exposure (scaling a deep signal down beats amplifying a shallow one), then the deepest stack.
  static func bestScalableDark(_ light: SetKey, _ masters: [CalibrationMaster], force: Bool) -> CalibrationMaster? {
    var best: CalibrationMaster?
    var bestDelta = Double.greatestFiniteMagnitude
    for master in masters where master.type == .dark && master.exposureMs != light.exposureMs {
      if !force && !master.sameCamera(as: light) { continue }
      let delta = master.temperatureDeltaC(to: light)
      if !force && delta > CalibrationMaster.temperatureToleranceC { continue }
      if let current = best {
        let deeper =
          master.exposureMs > current.exposureMs
          || (master.exposureMs == current.exposureMs && master.frameCount > current.frameCount)
        guard delta < bestDelta || (delta == bestDelta && deeper) else { continue }
      }
      best = master
      bestDelta = delta
    }
    return best
  }

  /// The single nearest dark whatever its settings — the forced last resort: smallest exposure
  /// gap, then temperature gap, then the deepest stack.
  static func closestDark(_ light: SetKey, _ masters: [CalibrationMaster]) -> CalibrationMaster? {
    masters.filter { $0.type == .dark }.enumerated().min { lhs, rhs in
      let left = (abs(lhs.element.exposureMs - light.exposureMs), abs(lhs.element.tempMilliC - light.tempBucketC * 1000))
      let right = (abs(rhs.element.exposureMs - light.exposureMs), abs(rhs.element.tempMilliC - light.tempBucketC * 1000))
      if left != right { return left < right }
      if lhs.element.frameCount != rhs.element.frameCount { return lhs.element.frameCount > rhs.element.frameCount }
      return lhs.offset < rhs.offset
    }?.element
  }

  /// A same-camera bias (forced: preferably same-camera, else any), the deepest first.
  static func bestBias(_ light: SetKey, _ masters: [CalibrationMaster], force: Bool) -> CalibrationMaster? {
    var best: CalibrationMaster?
    for master in masters where master.type == .bias {
      if !force && !master.sameCamera(as: light) { continue }
      if let current = best {
        let mine = master.sameCamera(as: light)
        let theirs = current.sameCamera(as: light)
        guard (mine && !theirs) || (mine == theirs && master.frameCount > current.frameCount) else { continue }
      }
      best = master
    }
    return best
  }

  /// The light's own filter, else any flat: a wrong-filter flat still removes the shared dust.
  static func bestFlat(_ light: SetKey, _ masters: [CalibrationMaster]) -> CalibrationMaster? {
    pickFlat(light, masters, sameFilter: true) ?? pickFlat(light, masters, sameFilter: false)
  }

  private static func pickFlat(
    _ light: SetKey, _ masters: [CalibrationMaster], sameFilter: Bool
  ) -> CalibrationMaster? {
    var best: CalibrationMaster?
    for master in masters where master.type == .flat && (!sameFilter || master.filter == light.filter) {
      if let current = best, !flatBeats(light, master, current) { continue }
      best = master
    }
    return best
  }

  /// Same night first, then the nearest other night (dust drifts with time), then the same
  /// camera, then depth. An undated flat ranks below every dated one on a multi-night run.
  private static func flatBeats(_ light: SetKey, _ master: CalibrationMaster, _ best: CalibrationMaster) -> Bool {
    let mine = nightScore(light.session, master.session)
    let theirs = nightScore(light.session, best.session)
    if mine != theirs { return mine > theirs }
    if mine == 0 {
      let gaps = (nightGapDays(light.session, master.session), nightGapDays(light.session, best.session))
      if gaps.0 != gaps.1 { return gaps.0 < gaps.1 }
    }
    let cameras = (master.sameCamera(as: light), best.sameCamera(as: light))
    if cameras.0 != cameras.1 { return cameras.0 }
    return master.frameCount > best.frameCount
  }

  /// 2 = same known night, 0 = another known night, -1 = the master's night is unknown;
  /// every candidate scores 1 for an undated (single-night) light.
  private static func nightScore(_ lightNight: String, _ masterNight: String) -> Int {
    if lightNight.isEmpty { return 1 }
    if lightNight == masterNight { return 2 }
    return masterNight.isEmpty ? -1 : 0
  }

  /// Days between two night keys; huge when either does not parse.
  private static func nightGapDays(_ lhs: String, _ rhs: String) -> Int {
    guard let left = day(lhs), let right = day(rhs) else { return Int(Int32.max) }
    return abs(Int(left.timeIntervalSince(right) / 86400))
  }

  private static func day(_ key: String) -> Date? {
    let millis = CaptureFrame.parseDateObs(key)
    return millis > 0 && key.count == 10 ? Date(timeIntervalSince1970: Double(millis) / 1000) : nil
  }
}
