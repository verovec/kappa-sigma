package import Foundation
package import StackKit

/// How the Objects card words a catalogue object (card 0130): its type, its list, its size and
/// magnitude, every number through `AstroFormat`.
package nonisolated enum SkyObjectWords {
  /// OpenNGC's type code in words; a code without words is shown as the catalogue gives it.
  package static func type(_ code: String, locale: Locale) -> String {
    let words: LocalizedStringResource? =
      switch code {
      case "G": .app("Galaxy", locale: locale)
      case "GPair": .app("Galaxy pair", locale: locale)
      case "GTrpl": .app("Galaxy triplet", locale: locale)
      case "GGroup": .app("Galaxy group", locale: locale)
      case "OCl": .app("Open cluster", locale: locale)
      case "GCl": .app("Globular cluster", locale: locale)
      case "Cl+N": .app("Cluster with nebulosity", locale: locale)
      case "*Ass": .app("Stellar association", locale: locale)
      case "PN": .app("Planetary nebula", locale: locale)
      case "HII": .app("H II region", locale: locale)
      case "EmN": .app("Emission nebula", locale: locale)
      case "RfN": .app("Reflection nebula", locale: locale)
      case "Neb": .app("Nebula", locale: locale)
      case "SNR": .app("Supernova remnant", locale: locale)
      case "DrkN": .app("Dark nebula", locale: locale)
      default: nil
      }
    return words.map { String(localized: $0) } ?? code
  }

  /// The list the object's designation comes from: catalogue names, the same in every language.
  package static func source(_ source: SkyObject.Source) -> String {
    switch source {
    case .messier: "Messier"
    case .ngc: "NGC"
    case .ic: "IC"
    case .sh2: "Sharpless (Sh2)"
    case .ldn: "Lynds (LDN)"
    }
  }

  /// `190′ × 70′`, `6′`, or nil when no size is known.
  package static func size(_ object: SkyObject, locale: Locale) -> String? {
    let format = AstroFormat(locale: locale)
    let axes = [object.majorAxisArcmin, object.minorAxisArcmin].compactMap { $0 }
    guard !axes.isEmpty else { return nil }
    return axes.map { format.decimal($0, maxFractionDigits: 1) + "′" }.joined(separator: " × ")
  }

  /// The magnitude, one decimal, or nil.
  package static func magnitude(_ object: SkyObject, locale: Locale) -> String? {
    object.magnitude.map { AstroFormat(locale: locale).decimal($0, maxFractionDigits: 1) }
  }
}
