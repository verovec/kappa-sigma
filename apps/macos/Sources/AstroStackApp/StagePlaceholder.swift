internal import RenderKit
internal import SwiftUI

/// The pane of a stage whose card has not landed: the empty state naming what will appear there,
/// with the stage's « ? » beside its title (card 0086).
struct StagePlaceholder: View {
  let stage: JourneyStage
  let title: LocalizedStringResource
  let message: LocalizedStringResource
  let systemImage: String
  @Environment(\.locale) private var locale

  var body: some View {
    EmptyState(
      title, message: message, systemImage: systemImage,
      help: StageHelp.help(stage, locale: locale))
  }
}
