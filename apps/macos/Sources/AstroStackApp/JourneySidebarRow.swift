internal import RenderKit
package import SwiftUI

/// One stage of the journey sidebar: its glossary term, its state's badge, and its accessibility
/// label and identifier (`AccessibilityID.journeyStage`).
package struct JourneySidebarRow: View {
  let stage: JourneyStage
  let status: StageStatus
  @Environment(\.locale) private var locale

  /// The row of `stage` in `status`.
  package init(stage: JourneyStage, status: StageStatus) {
    self.stage = stage
    self.status = status
  }

  package var body: some View {
    let term = AppGlossary.label(stage.termID, locale: locale)
    HStack(spacing: DesignMetrics.spacingS) {
      Text(verbatim: term)
      Spacer(minLength: DesignMetrics.spacingXS)
      indicator
    }
    // The stage card's first line (card 0086); its state is the accessibility value.
    .help(
      StageHelp.summary(stage, locale: locale).map { Text(verbatim: $0) }
        ?? Text(StagePane.words(for: status))
    )
    .accessibilityElement(children: .combine)
    .accessible(.journeyStage(stage.rawValue), verbatim: term)
    .accessibilityValue(Text(StagePane.words(for: status)))
  }

  @ViewBuilder private var indicator: some View {
    if status == .running {
      ProgressView().controlSize(.small)
    } else if let badge = StagePane.badge(for: status) {
      HStack(spacing: DesignMetrics.spacingXXS) {
        if case .attention(let count) = status {
          Text(verbatim: LocaleNumber.integer(count, locale: locale))
            .font(.caption.monospacedDigit())
        }
        Image(systemName: badge.systemImage)
      }
      .foregroundStyle(badge.token.color)
    }
  }
}
