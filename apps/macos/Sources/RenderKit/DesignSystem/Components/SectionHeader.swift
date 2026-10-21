package import Foundation
package import SwiftUI

/// A section's title and, under it, one line on what the section holds.
package struct SectionHeader: View {
  private let title: LocalizedStringResource
  private let detail: LocalizedStringResource?

  /// The header `title`, with an optional `detail` line.
  package init(_ title: LocalizedStringResource, detail: LocalizedStringResource? = nil) {
    self.title = title
    self.detail = detail
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
      Text(title).font(.headline).foregroundStyle(DesignColor.textPrimary.color)
      if let detail {
        Text(detail).font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
    }
    .accessibilityAddTraits(.isHeader)
  }
}
