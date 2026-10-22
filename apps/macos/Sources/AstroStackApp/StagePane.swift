package import Foundation
package import RenderKit
internal import SwiftUI

/// The one place that maps a journey stage to its pane and its state's badge and words.
///
/// A stage whose card has not landed shows an empty state naming what will appear there — no fake
/// controls. A card that builds a stage's pane replaces its case here (0071/0078 calibration,
/// 0069 review, E12 studio processes, 0091 export).
package enum StagePane {
  /// The pane of `stage`.
  @ViewBuilder
  static func pane(for stage: JourneyStage, model: ProjectWindowModel) -> some View {
    switch stage {
    case .data:
      DataStagePane(model: model)
    case .calibration:
      CalibrationStagePane(model: model)
    case .review:
      ReviewStagePane(model: model)
    case .stacking:
      StackingStagePane(model: model)
    case .studio:
      StudioStagePane(model: model)
    case .export:
      EmptyState(
        .app("Export"),
        message: .app("The deliverables written from the finished image will appear here."),
        systemImage: "square.and.arrow.up")
    }
  }

  /// The sidebar badge of `status`; `nil` where the stage name says enough.
  package nonisolated static func badge(for status: StageStatus) -> DesignStatus? {
    switch status {
    case .done: .ok
    case .attention: .attention
    case .unavailable: .unavailable
    case .toDo, .ready, .running: nil
    }
  }

  /// What `status` means, for the tooltip and VoiceOver.
  package nonisolated static func words(
    for status: StageStatus, locale: Locale? = nil
  ) -> LocalizedStringResource {
    switch status {
    case .toDo: .app("To do", locale: locale)
    case .ready: .app("Ready", locale: locale)
    case .running: .app("Running", locale: locale)
    case .attention(let count): .app("\(count) to check", locale: locale)
    case .done: .app("Done", locale: locale)
    case .unavailable(.needsSources): .app("Import captures first", locale: locale)
    case .unavailable(.needsStack): .app("Stack a night first", locale: locale)
    }
  }
}
