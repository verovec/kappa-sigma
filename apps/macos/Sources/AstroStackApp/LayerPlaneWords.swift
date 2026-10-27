import FilterKit
package import Foundation
import ProcessKit

/// A layer token in the view's language (card 0139): a layer as the switcher names it
/// (`StudioSelection.label`: glossary words, a custom id verbatim), `A*B` as « A × B », a plane
/// by its colour.
package enum LayerPlaneWords {
  /// `token` worded in `locale`.
  package static func words(_ token: String, locale: Locale) -> String {
    if token == "none" { return String(localized: .app("None", locale: locale)) }
    let parts = token.split(separator: "*").map(String.init)
    if parts.count == 2 {
      return parts.map { layer($0, locale: locale) }.joined(separator: " × ")
    }
    let plane = LayerPlane(token)
    let words = layer(plane.layer, locale: locale)
    guard plane.token != plane.layer else { return words }
    // The plane's filter from the one plane list (`r` → `R`): its glossary word, lowercased.
    let name = LayerPlane.planeNames[plane.plane]
    let colour = Filter(rawValue: name.uppercased()).map {
      AppGlossary.label($0.termID, locale: locale).lowercased(with: locale)
    }
    return words + " · " + (colour ?? name)
  }

  /// A layer id in words: what the switcher calls the layer, the one naming rule.
  private static func layer(_ id: String, locale: Locale) -> String {
    StudioSelection.label(.branch(id), locale: locale)
  }
}
