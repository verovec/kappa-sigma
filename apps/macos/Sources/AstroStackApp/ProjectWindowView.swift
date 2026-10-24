internal import RenderKit
package import SwiftUI

/// The content of a project window: the journey sidebar (Données → … → Export, each stage with
/// its state) and the selected stage's pane.
///
/// The sidebar shows where the project stands; only the user (or the first-stack guide they
/// opened, in its side panel) moves the selection.
package struct ProjectWindowView: View {
  @State var model: ProjectWindowModel

  /// A window showing the project behind `model`.
  package init(model: ProjectWindowModel) {
    _model = State(initialValue: model)
  }

  package var body: some View {
    NavigationSplitView {
      JourneySidebar(model: model)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    } detail: {
      VStack(spacing: 0) {
        // The card covers the stage, never replaces it: the Studio's viewer stays as it was.
        StagePane.pane(for: model.selection, model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          // Covered, the stage neither reads out nor takes a click.
          .accessibilityHidden(model.objects.cardShown)
          .allowsHitTesting(!model.objects.cardShown)
          .overlay {
            if model.objects.cardShown, let object = model.objects.selected {
              ObjectCard(object: object) { model.objects.closeCard() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(DesignColor.surface.color)
            }
          }
        if let error = model.error {
          StatusBadge(.error, error.message)
            .padding(DesignMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .inspector(
      isPresented: Binding(
        get: { model.guideStep != nil }, set: { if !$0 { model.closeGuide() } })
    ) {
      if let step = model.guideStep {
        GuidePanel(model: model, step: step)
          .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .sheet(
      isPresented: Binding(
        get: { model.importing != nil }, set: { if !$0 { model.closeImport() } })
    ) {
      if let importing = model.importing {
        ImportSheet(
          model: importing, onAdd: { model.add($0) }, onCancel: { model.closeImport() },
          addError: model.importError
        )
        // A sheet is its own window: set again so the ring reaches the profile picker whatever
        // the sheet inherits.
        .environment(\.guideTarget, model.guideTarget)
      }
    }
    .environment(\.guideTarget, model.guideTarget)
  }
}
