import FilterKit
package import Foundation
import ProcessKit

/// A layer token in the view's language (card 0139): the colour layer and the broadband filters
/// by their glossary words, a line by its name, `A*B` as « A × B », a custom id verbatim.
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
    guard plane.token != plane.layer, plane.plane < LayerPlane.planeNames.count else {
      return words
    }
    let colour = [Filter.red, .green, .blue][plane.plane]
    return words + " · " + AppGlossary.label(colour.termID, locale: locale).lowercased(with: locale)
  }

  /// A layer id in words: a line's name, else what the switcher calls the layer.
  private static func layer(_ id: String, locale: Locale) -> String {
    if let line = Filter(rawValue: id)?.line { return line.displayName }
    return StudioSelection.label(.branch(id), locale: locale)
  }
}
