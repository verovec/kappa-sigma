package import Foundation
package import SwiftUI

/// A measured value: its label, the number in equal-width digits, its unit, change and verdict.
///
/// Values arrive formatted (the app's `AstroFormat`): RenderKit never imports the app.
package struct MetricValue: View {
  private let label: LocalizedStringResource
  private let value: String
  private let unit: String?
  private let delta: String?
  private let status: DesignStatus?

  /// `value` already written in the user's locale; `unit` (« ADU », « px »), `delta` (« +12 »).
  package init(
    _ label: LocalizedStringResource, value: String, unit: String? = nil, delta: String? = nil,
    status: DesignStatus? = nil
  ) {
    self.label = label
    self.value = value
    self.unit = unit
    self.delta = delta
    self.status = status
  }

  package var body: some View {
    LabeledContent {
      HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingXS) {
        if let status {
          Image(systemName: status.systemImage).foregroundStyle(status.token.color)
        }
        Text(verbatim: value).font(DesignMetrics.valueFont)
          .foregroundStyle(DesignColor.textPrimary.color)
        if let unit {
          Text(verbatim: unit).font(DesignMetrics.captionFont)
            .foregroundStyle(DesignColor.textSecondary.color)
        }
        if let delta {
          Text(verbatim: delta).font(DesignMetrics.captionFont)
            .foregroundStyle(DesignColor.textSecondary.color)
        }
      }
    } label: {
      Text(label)
    }
    .accessibilityElement(children: .combine)
  }
}
