package import Foundation
internal import ProcessKit

/// What the combined image holds at its head (card 0131), said under « Combined »: before line
/// injection a BB + DB stack's combined image is the broadband alone, and a step reading the head
/// (colour calibration) sees no line.
package struct CombinedContents: Equatable, Sendable {
  /// The bundle layers in the image, in the switcher's order.
  package let holds: [String]
  /// The bundle layers not in it, in the switcher's order.
  package let missing: [String]

  /// The layers `holds` in, `missing` out.
  package init(holds: [String], missing: [String]) {
    self.holds = holds
    self.missing = missing
  }

  /// The line under « Combined » in `locale`: the layers in, then those out — with the
  /// processes that lay lines in when the ones out are all lines over a broadband base.
  package func words(locale: Locale) -> LocalizedStringResource {
    let names = { (ids: [String]) in
      ids.map { StudioSelection.label(.branch($0), locale: locale) }
    }
    // « + » reads alike in both languages: the layers are summed into one image.
    let holding = names(holds).joined(separator: " + ")
    guard !missing.isEmpty else { return .app("Holds \(holding).", locale: locale) }
    let out = names(missing).formatted(.list(type: .and).locale(locale))
    // The two processes lay lines over a broadband base only (line injection refuses another).
    guard holds.contains("RGB"), missing.allSatisfy(EmissionLine.layerIDs.contains) else {
      return .app("Holds \(holding); not \(out).", locale: locale)
    }
    let title = { (title: String) in
      String(localized: ProcessKitResources.title(title, locale: locale))
    }
    let (injection, screens) = (
      title(LineInjectionProcess.title), title(EmissionScreensProcess.title)
    )
    return .app(
      "Holds \(holding); not yet \(out) (to add with \(injection) or \(screens)).", locale: locale)
  }
}
