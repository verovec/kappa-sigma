package import Foundation
internal import HelpKit
package import RenderKit

/// The first-stack guide (card 0061, design §6): seven steps from Import to Export, each pointing
/// at the real control by its accessibility identifier.
///
/// It opens only from Help › First-Stack Guide, never by itself; the step reached is remembered
/// per project. The text is HelpKit's `guide/first-stack.md`, one line per step.
package nonisolated enum FirstStackGuide {
  /// One step: the stage it shows and the control it points at.
  package struct Step: Equatable, Sendable {
    /// The journey stage selected when the step is shown.
    package let stage: JourneyStage
    /// The control ringed (`guideTarget`).
    package let target: AccessibilityID
  }

  /// The steps, in order.
  ///
  /// Import, sort and profile, plan, run, the stack, stretch then screens, export. The Studio's
  /// process panels have no card yet: the finishing steps point at their stage.
  package static let steps: [Step] = [
    Step(stage: .data, target: .importCaptures),
    Step(stage: .data, target: .importProfile),
    Step(stage: .calibration, target: .journeyStage(JourneyStage.calibration.rawValue)),
    Step(stage: .stacking, target: .stackingRun),
    Step(stage: .studio, target: .journeyStage(JourneyStage.studio.rawValue)),
    Step(stage: .studio, target: .journeyStage(JourneyStage.studio.rawValue)),
    Step(stage: .export, target: .journeyStage(JourneyStage.export.rawValue)),
  ]

  /// The `project_settings` key of the step a project's guide last showed (UI state only).
  static let settingKey = "guide.step"

  /// The text of step `index` in the language of `locale` (`HelpMarkdown` source).
  package static func text(_ index: Int, locale: Locale) -> String {
    let steps = texts[AppLocale.language(of: locale)] ?? []
    return steps.indices.contains(index) ? steps[index] : ""
  }

  /// Each locale's steps, read once: the panel's body asks on every redraw.
  private static let texts = Dictionary(
    uniqueKeysWithValues: HelpIndex.locales.map { ($0, AppGlossary.help.guide(locale: $0)) })
}
