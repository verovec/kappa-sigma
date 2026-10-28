internal import RenderKit
package import SwiftUI

/// The content of a project window: the journey sidebar (Données → … → Export, each stage with
/// its state) and the selected stage's pane.
///
/// The sidebar shows where the project stands; only the user (or the first-stack guide they
/// opened, in its side panel) moves the selection.
package struct ProjectWindowView: View {
  @State var model: ProjectWindowModel
  /// The journey sidebar as the user left it; the full-screen image hides it over this value.
  @State private var sidebarStored = NavigationSplitViewVisibility.automatic

  /// Where the project switcher's projects come from (card 0146): `.live` in the app.
  let projects: ProjectSwitcher.Source

  /// A window showing the project behind `model`.
  package init(model: ProjectWindowModel, projects: ProjectSwitcher.Source) {
    _model = State(initialValue: model)
    self.projects = projects
  }

  /// What the switcher's head says for `model`: the target of a saved project, nothing for an
  /// untitled one (its temporary package is named by a UUID, never shown).
  package static func head(for model: ProjectWindowModel) -> (target: String, current: URL?) {
    model.isSaved() ? (model.targetName, model.folder()) : ("", nil)
  }

  /// The sidebar shown: hidden while the Studio's image is focused (card 0127), else as the user
  /// left it (`stored`, never changed by the focus).
  package static func sidebar(
    stored: NavigationSplitViewVisibility, focused: Bool
  ) -> NavigationSplitViewVisibility {
    focused ? .detailOnly : stored
  }

  package var body: some View {
    let focused = model.workspace?.isFocused == true
    NavigationSplitView(
      columnVisibility: Binding(
        get: { Self.sidebar(stored: sidebarStored, focused: focused) },
        set: { if !focused { sidebarStored = $0 } })
    ) {
      JourneySidebar(model: model, switcher: switcher)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    } detail: {
      VStack(spacing: 0) {
        // The card covers the stage, never replaces it: the Studio's viewer stays as it was.
        StagePane.pane(for: model.selection, model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          // Covered, the stage neither reads out nor takes a click.
          .accessibilityHidden(model.objects.coversStage)
          .allowsHitTesting(!model.objects.coversStage)
          .overlay {
            if model.objects.coversStage, let object = model.objects.selected {
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

  /// The switcher at the head of the sidebar (card 0146).
  private var switcher: ProjectSwitcher {
    let head = Self.head(for: model)
    return ProjectSwitcher(target: head.target, current: head.current, source: projects)
  }
}
