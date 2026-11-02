package import Foundation
package import StackKit
package import SwiftUI

/// The capture folders of one import, or the ones it dropped, as the Import sheet lists them on
/// click (card 0174).
///
/// The list sizes itself to its rows; from `scrollingLines` lines of text (a dropped row takes two)
/// it scrolls within `maxHeight`, so a whole season never outgrows the screen and a short list never
/// hides a row behind a guess.
package struct ImportFolderList: View {
  private enum Row: Hashable {
    case folder(String)
    case dropped(ImportFolders.Nested)
  }

  /// The list's width, in points: a long path truncates in its middle.
  package static let width: CGFloat = 520
  /// The height of the scrolling list, in points.
  package static let maxHeight: CGFloat = 360
  /// From this many lines of text the list scrolls: about `maxHeight` of body text.
  package static let scrollingLines = 16
  /// The words before the ancestor of a dropped row.
  package static let includedIn: LocalizedStringResource = .app("already included in")

  private let rows: [Row]

  /// A list of `folders`, in the order the scan reads them (the first is the primary one).
  package init(folders: [String]) {
    rows = folders.map(Row.folder)
  }

  /// A list of the `dropped` folders, each with the chosen folder that covers it.
  package init(dropped: [ImportFolders.Nested]) {
    rows = dropped.map(Row.dropped)
  }

  /// Whether a list of `lines` lines of text scrolls.
  package static func scrolls(lines: Int) -> Bool {
    lines >= scrollingLines
  }

  /// The lines of text of the rows: a folder takes one, a dropped folder two.
  private var lines: Int {
    rows.reduce(0) { lines, row in
      if case .dropped = row { lines + 2 } else { lines + 1 }
    }
  }

  package var body: some View {
    Group {
      if Self.scrolls(lines: lines) {
        ScrollView { list }
          .scrollBounceBehavior(.basedOnSize)
          .frame(height: Self.maxHeight)
      } else {
        list
      }
    }
    .font(.body)
    .frame(width: Self.width)
    .padding()
  }

  private var list: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(rows, id: \.self) { row in
        switch row {
        case .folder(let folder):
          Self.path(folder)
        case .dropped(let nested):
          VStack(alignment: .leading, spacing: 1) {
            Self.path(nested.path)
            HStack(spacing: 4) {
              Text(Self.includedIn).fixedSize()
              Self.path(nested.ancestor)
            }
            .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private static func path(_ path: String) -> some View {
    Text(verbatim: path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
  }
}
