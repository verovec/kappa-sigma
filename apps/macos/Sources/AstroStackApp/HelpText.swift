internal import HelpKit
internal import RenderKit
package import SwiftUI

/// Help content written in `HelpMarkdown`, drawn as text (card 0061).
///
/// Paragraphs, bulleted items, bold and italic; anything else was already plain text in the parse.
package struct HelpText: View {
  let blocks: [HelpMarkdown.Block]

  /// `source` rendered.
  package init(_ source: String) {
    blocks = HelpMarkdown.parse(source)
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      ForEach(blocks.indices, id: \.self) { index in
        switch blocks[index] {
        case .paragraph(let runs):
          Self.text(runs)
        case .item(let runs):
          HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingXS) {
            Text(verbatim: "•")
            Self.text(runs)
          }
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// `runs` as one text, each with its emphasis.
  static func text(_ runs: [HelpMarkdown.Run]) -> Text {
    runs.reduce(Text(verbatim: "")) { text, run in
      Text("\(text)\(Text(verbatim: run.text).bold(run.bold).italic(run.italic))")
    }
  }
}
