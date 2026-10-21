package import Foundation
package import HelpKit
internal import RenderKit
package import SwiftUI

/// Help › Glossary (card 0079): every term the app uses, its label and definition in the
/// interface language, filtered by a search field.
package struct GlossaryView: View {
  @State private var query = ""
  @Environment(\.locale) private var locale

  /// The glossary.
  package init() {}

  /// A term and its id (the list's identity: labels may repeat across vocabularies).
  nonisolated package struct Entry: Sendable {
    /// The glossary id (`stage.data`).
    package let id: String
    /// Its label and definition in the window's language.
    package let term: Glossary.Term
  }

  /// The terms whose label or definition contains `query` (case and accents aside), sorted by
  /// label in `locale`; an empty query keeps them all.
  package nonisolated static func terms(matching query: String, locale: Locale) -> [Entry] {
    let query = query.trimmingCharacters(in: .whitespaces)
    let entries = Set(AppGlossary.termIDs).map {
      Entry(id: $0, term: AppGlossary.term($0, locale: locale))
    }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    return entries.filter { entry in
      let term = entry.term
      return
        query.isEmpty || term.label.range(of: query, options: options, locale: locale) != nil
        || term.definition.range(of: query, options: options, locale: locale) != nil
    }
    .sorted {
      $0.term.label.compare($1.term.label, options: options, locale: locale) == .orderedAscending
    }
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      TextField(text: $query) { Text(.app("Search the glossary")) }
        .textFieldStyle(.roundedBorder)
        .accessible(.glossarySearch, label: .app("Search the glossary"))
      List(Self.terms(matching: query, locale: locale), id: \.id) { entry in
        VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
          Text(verbatim: entry.term.label).font(.headline)
          Text(verbatim: entry.term.definition)
            .foregroundStyle(DesignColor.textSecondary.color)
        }
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(minWidth: 420, minHeight: 480)
  }
}
