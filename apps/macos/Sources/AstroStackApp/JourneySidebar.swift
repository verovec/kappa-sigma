internal import Foundation
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
    // List rows are table cells: their audit entries do not leave the List, so the List reports
    // them, from the same `accessibility(of:)` each row applies.
    .transformPreference(AccessibilityAudit.Key.self) { entries in
      entries += JourneyStage.allCases.map { stage in
        let (id, label) = Self.accessibility(of: stage, locale: locale)
        return AccessibilityAudit.Entry(id: id.rawValue, label: label)
      }
    }
  }

  /// The identifier and label of the row of `stage`: its glossary term in `locale`.
  nonisolated static func accessibility(of stage: JourneyStage, locale: Locale)
    -> (AccessibilityID, String)
  {
    (.journeyStage(stage.rawValue), AppGlossary.label(stage.termID, locale: locale))
  }

  private func row(_ stage: JourneyStage, status: StageStatus) -> some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Text(verbatim: AppGlossary.label(stage.termID, locale: locale))
      Spacer(minLength: DesignMetrics.spacingXS)
      indicator(status)
    }
    .help(Text(StagePane.words(for: status)))
    .accessibilityElement(children: .combine)
    .accessible(
      Self.accessibility(of: stage, locale: locale).0,
      verbatim: Self.accessibility(of: stage, locale: locale).1
    )
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
