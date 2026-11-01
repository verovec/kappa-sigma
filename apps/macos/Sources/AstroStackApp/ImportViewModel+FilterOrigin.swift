package import Foundation
package import StackKit

/// Where each light filter row's verdict came from (card 0163): shown next to its picker, the
/// picker still winning (R2).
extension ImportViewModel {
  /// The verdict of the light filter row `filter` and where its frames' filter came from, `nil`
  /// when the scan has no such row or did not say: a mapped row names the user's mapping and the
  /// filter it became; a row spanning several sets (nights, exposures) lists each distinct origin.
  package func detected(_ filter: String) -> (verdict: String, origins: [FilterOrigin])? {
    let lights = plan?.inventory.sets.filter { $0.key.type == .light } ?? []
    if request.filterMap[filter] != nil {
      let origin = FilterOrigin(source: .manual, raw: filter)
      return lights.first { $0.filterOrigins.contains(origin) }.map { ($0.key.filter, [origin]) }
    }
    let origins = lights.filter { $0.key.filter == filter }.flatMap(\.filterOrigins)
      .reduce(into: [FilterOrigin]()) { if !$0.contains($1) { $0.append($1) } }
    return origins.isEmpty ? nil : (filter, origins)
  }

  /// The row's lines, « Ha — FITS FILTER « H-alpha 7nm » », one per origin, in `locale` (the
  /// user's by default).
  package func originWords(of filter: String, locale: Locale? = nil) -> [LocalizedStringResource] {
    guard let (verdict, origins) = detected(filter) else { return [] }
    return origins.map { Self.originWords(verdict: verdict, origin: $0, locale: locale) }
  }

  /// « `verdict` — where `origin` read it ».
  package nonisolated static func originWords(
    verdict: String, origin: FilterOrigin, locale: Locale? = nil
  ) -> LocalizedStringResource {
    let raw = origin.raw
    return switch origin.source {
    case .header: .app("\(verdict) — FITS FILTER « \(raw) »", locale: locale)
    case .fileName: .app("\(verdict) — file name « \(raw) »", locale: locale)
    case .folder: .app("\(verdict) — folder « \(raw) »", locale: locale)
    case .manifest: .app("\(verdict) — info.txt legend « \(raw) »", locale: locale)
    case .wheelSlot: .app("\(verdict) — filter-wheel slot \(raw)", locale: locale)
    case .signal: .app("\(verdict) — detected from the signal (wheel order)", locale: locale)
    case .manual: .app("\(verdict) — your mapping of « \(raw) »", locale: locale)
    }
  }
}
