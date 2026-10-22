package import Foundation
package import SwiftUI

/// A section's title and, under it, one line on what the section holds; beside the title, its
/// « ? » when the section has help (card 0086).
package struct SectionHeader: View {
  private let title: LocalizedStringResource
  private let detail: LocalizedStringResource?
  private let help: KeyedHelp?

  /// The header `title`, with an optional `detail` line and, with `help`, its « ? ».
  package init(
    _ title: LocalizedStringResource, detail: LocalizedStringResource? = nil, help: KeyedHelp? = nil
  ) {
    self.title = title
    self.detail = detail
    self.help = help
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
      HStack(spacing: DesignMetrics.spacingS) {
        Text(title).font(.headline).foregroundStyle(DesignColor.textPrimary.color)
        if let help { help.button }
      }
      if let detail {
        Text(detail).font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
    }
    .accessibilityAddTraits(.isHeader)
  }
}
