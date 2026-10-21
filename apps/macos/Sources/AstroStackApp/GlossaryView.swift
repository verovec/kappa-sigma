package import AppKit
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

  /// The terms whose label or definition contains `query` (case and accents aside), sorted by
  /// label in `locale`; an empty query keeps them all.
  package nonisolated static func terms(matching query: String, locale: Locale) -> [Glossary.Term] {
    let query = query.trimmingCharacters(in: .whitespaces)
    let terms = Set(AppGlossary.termIDs).map { AppGlossary.term($0, locale: locale) }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    return terms.filter { term in
      query.isEmpty || term.label.range(of: query, options: options, locale: locale) != nil
        || term.definition.range(of: query, options: options, locale: locale) != nil
    }
    .sorted { $0.label.compare($1.label, options: options, locale: locale) == .orderedAscending }
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      TextField(text: $query) { Text(.app("Search the glossary")) }
        .textFieldStyle(.roundedBorder)
        .accessible(.glossarySearch, label: .app("Search the glossary"))
      List(Self.terms(matching: query, locale: locale), id: \.label) { term in
        VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
          Text(verbatim: term.label).font(.headline)
          Text(verbatim: term.definition).foregroundStyle(DesignColor.textSecondary.color)
        }
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(minWidth: 420, minHeight: 480)
  }
}

/// Help › Glossary: one window, reused.
package enum GlossaryWindow {
  private static var window: NSWindow?

  /// Shows the window, creating it the first time.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private static func make() -> NSWindow {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: GlossaryView().background(DesignColor.surface.color).interfaceLocale()))
    window.title = String(localized: .app("Glossary"))
    window.styleMask = [.titled, .closable, .resizable]
    window.isReleasedWhenClosed = false
    return window
  }
}
