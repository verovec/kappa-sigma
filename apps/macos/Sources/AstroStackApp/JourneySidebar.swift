internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The stages of the journey, in working order, each with its state; selecting one shows its
/// pane and is remembered for the project.
///
/// Under them, the Objects of Siril's catalogue, searched from the sidebar's field (card 0130).
struct JourneySidebar: View {
  var model: ProjectWindowModel
  /// The project switcher at the head of the list (card 0146); none in a bare sidebar.
  var switcher: ProjectSwitcher?

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
      if let switcher {
        Section { switcher }
      }
      Section {
        ForEach(JourneyStage.allCases, id: \.self) { stage in
          JourneySidebarRow(stage: stage, status: model.statuses[stage] ?? .toDo)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // The stage already selected sets no new selection: a click anywhere on its row
            // closes the card too.
            .simultaneousGesture(TapGesture().onEnded { objects.closeCard() })
            .tag(stage)
        }
      }
      ObjectsSection(objects: objects)
    }
    .listStyle(.sidebar)
    // Restarted (the previous one cancelled) when the stack's object changes or Siril comes back.
    .task(
      id: LoadKey(
        object: model.projectObjectName.map(SkyCatalogue.normalize), reloads: objects.reloads)
    ) {
      await objects.load(projectObject: model.projectObjectName)
    }
    // Siril found by the install card's « Re-check »: the catalogue is read again.
    .onChange(of: objects.sirilCard?.state) { _, state in
      if case .found = state { objects.retry() }
    }
    .searchable(text: $objects.query, placement: .sidebar, prompt: Text(.app("Search objects")))
  }
}

/// What the sidebar's catalogue load depends on.
private struct LoadKey: Equatable {
  /// The project's object, normalised: a respelling is the same object.
  let object: String?
  let reloads: Int
}
