internal import FilterKit
package import Foundation
internal import StackKit

/// Which history the Studio shows and edits (card 0119): the combined image, or one bundle
/// layer's branch before the combination (card 0118).
package enum StudioSelection: Hashable, Sendable {
  /// The main history: the combined image.
  case main
  /// The branch of a bundle layer, by its id (`RGB`, `Ha`, `OIII`).
  case branch(String)

  /// The help card the switcher's « ? » opens (`stage/branches.md`).
  package nonisolated static let helpCard = "branches"

  /// The glossary terms the switcher shows besides the filter words.
  package nonisolated static let termIDs = ["studio.combined", "studio.branch"]

  /// What the switcher calls `selection` in `locale`: glossary words, never a raw id — the
  /// broadband colour layer under its filter-set word, a line under its filter's.
  package static func label(_ selection: Self, locale: Locale) -> String {
    switch selection {
    case .main:
      return AppGlossary.label("studio.combined", locale: locale)
    case .branch(let id) where id == "RGB":
      return AppGlossary.label(FilterSet.broadband.termID, locale: locale) + " (RGB)"
    case .branch(let id):
      return Filter(rawValue: id).map { AppGlossary.label($0.termID, locale: locale) } ?? id
    }
  }

  /// The layer it edits, `nil` for the main history.
  package var layerID: String? {
    if case .branch(let id) = self { id } else { nil }
  }
}
