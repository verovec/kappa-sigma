internal import RenderKit
internal import SwiftUI

/// The stages of the journey, in working order, each with its state; selecting one shows its
/// pane and is remembered for the project.
struct JourneySidebar: View {
  var model: ProjectWindowModel

  var body: some View {
    List(
      selection: Binding(
        get: { model.selection }, set: { stage in if let stage { model.select(stage) } })
    ) {
      ForEach(JourneyStage.allCases, id: \.self) { stage in
        JourneySidebarRow(stage: stage, status: model.statuses[stage] ?? .toDo).tag(stage)
      }
    }
    .listStyle(.sidebar)
  }
}
