internal import Foundation
internal import StackKit

/// How a light set of the coverage is named, the same in Données and Calibration.
extension CoverageMatrix {
  /// « RGB · dual-band · 300 s · 2026-09-22 », with the sensor settings and temperature cluster
  /// (« g100 o50 b1 · −17 °C ») when another light set would read the same.
  func heading(_ row: Row, locale: Locale) -> String {
    let base = baseHeading(row, locale: locale)
    guard rows.filter({ baseHeading($0, locale: locale) == base }).count > 1 else { return base }
    let key = row.channel.key
    // A cluster of frames without CCD-TEMP sits at bucket 0: never show it as « 0 °C ».
    let temperature =
      row.temperatureRecorded ? ImportFormat.temperature(key, in: AstroFormat(locale: locale)) : "—"
    return [base, ImportFormat.sensor(key), temperature].joined(separator: " · ")
  }

  private func baseHeading(_ row: Row, locale: Locale) -> String {
    let format = AstroFormat(locale: locale)
    let parts =
      [
        ImportFormat.filter(row.channel.filter, filterSet: row.filterSet, locale: locale),
        format.exposure(ms: row.channel.key.exposureMs),
      ] + (row.night.isEmpty ? [] : [row.night])
    let object = row.channel.key.object
    let target = targets > 1 && !object.isEmpty ? [object] : []
    return (target + parts).joined(separator: " · ")
  }
}
