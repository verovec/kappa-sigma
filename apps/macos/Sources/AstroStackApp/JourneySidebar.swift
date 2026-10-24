internal import RenderKit
internal import SwiftUI

/// The stages of the journey, in working order, each with its state; selecting one shows its
/// pane and is remembered for the project.
///
/// Under them, the Objects of Siril's catalogue, searched from the sidebar's field (card 0130).
struct JourneySidebar: View {
  var model: ProjectWindowModel

  var body: some View {
    @Bindable var objects = model.objects
    List(
      selection: Binding(
        get: { model.selection },
        set: { stage in
          guard let stage else { return }
          // A stage chosen takes the detail column back from an object card.
          objects.closeCard()
          model.select(stage)
        })
    ) {
      Section {
        ForEach(JourneyStage.allCases, id: \.self) { stage in
          JourneySidebarRow(stage: stage, status: model.statuses[stage] ?? .toDo).tag(stage)
        }
      }
      ObjectsSection(objects: objects, projectObject: model.projectObjectName)
    }
    .listStyle(.sidebar)
    .searchable(text: $objects.query, placement: .sidebar, prompt: Text(.app("Search objects")))
  }
}
