package import Foundation
internal import RenderKit
package import SwiftUI

/// Help › Keyboard Shortcuts (card 0079): every `CommandCatalog` command with its shortcut,
/// app-wide commands first, then by journey stage, filtered by a search field.
package struct ShortcutsSheet: View {
  /// One command as the sheet lists it.
  nonisolated package struct Row: Equatable, Sendable {
    /// The command id.
    package let id: String
    /// Its title in the sheet's language.
    package let title: String
    /// Its shortcut as macOS writes it (`⇧⌘O`), empty when it has none.
    package let shortcut: String
  }

  /// The commands of one stage (`nil`: app-wide).
  nonisolated package struct Group: Equatable, Sendable {
    /// The stage, `nil` for the app-wide commands.
    package let stage: JourneyStage?
    /// Its title: the stage's glossary term, or « General ».
    package let title: String
    /// Its commands, in catalog order.
    package let rows: [Row]
  }

  @State private var query = ""
  @Environment(\.locale) private var locale

  /// The sheet.
  package init() {}

  /// The groups whose commands match `query` (title containing it, case and accents aside, or
  /// the exact shortcut), in `locale`; an empty query keeps every command.
  package nonisolated static func groups(matching query: String, locale: Locale) -> [Group] {
    let stages: [JourneyStage?] = [nil] + JourneyStage.allCases.map(Optional.some)
    return stages.compactMap { stage -> Group? in
      let rows = CommandCatalog.commands.filter { $0.isBuilt && $0.stage == stage }.map { command in
        Row(
          id: command.id, title: String(localized: command.title(locale: locale)),
          shortcut: command.shortcut?.symbols ?? "")
      }.filter { matches($0, query, locale: locale) }
      guard !rows.isEmpty else { return nil }
      let title =
        stage.map { AppGlossary.label($0.termID, locale: locale) }
        ?? String(localized: .app("General", locale: locale))
      return Group(stage: stage, title: title, rows: rows)
    }
  }

  private nonisolated static func matches(_ row: Row, _ query: String, locale: Locale) -> Bool {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return true }
    if row.shortcut == query { return true }
    return row.title.range(
      of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      TextField(text: $query) { Text(.app("Search shortcuts")) }
        .textFieldStyle(.roundedBorder)
        .accessible(.shortcutsSearch, label: .app("Search shortcuts"))
      List {
        ForEach(Self.groups(matching: query, locale: locale), id: \.title) { group in
          Section {
            ForEach(group.rows, id: \.id) { row in
              HStack {
                Text(verbatim: row.title)
                Spacer()
                Text(verbatim: row.shortcut).font(DesignMetrics.valueFont)
                  .foregroundStyle(DesignColor.textSecondary.color)
              }
            }
          } header: {
            Text(verbatim: group.title)
          }
        }
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(minWidth: 420, minHeight: 480)
  }
}
