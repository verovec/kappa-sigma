internal import RenderKit
internal import SwiftUI

/// The stages of the journey, in working order, each with its state; selecting one shows its
/// pane and is remembered for the project.
struct JourneySidebar: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    List(
      selection: Binding(
        get: { model.selection }, set: { stage in if let stage { model.select(stage) } })
    ) {
      ForEach(JourneyStage.allCases, id: \.self) { stage in
        row(stage, status: model.statuses[stage] ?? .toDo).tag(stage)
      }
    }
    .listStyle(.sidebar)
  }

  private func row(_ stage: JourneyStage, status: StageStatus) -> some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Text(verbatim: AppGlossary.label(stage.termID, locale: locale))
      Spacer(minLength: DesignMetrics.spacingXS)
      indicator(status)
    }
    .help(Text(StagePane.words(for: status)))
    .accessibilityElement(children: .combine)
    .accessibilityValue(Text(StagePane.words(for: status)))
  }

  @ViewBuilder
  private func indicator(_ status: StageStatus) -> some View {
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
