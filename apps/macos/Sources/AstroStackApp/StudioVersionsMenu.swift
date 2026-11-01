package import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Versions menu above the Studio's history (card 0159): each chain a revise or a restore
/// put aside, compared with the viewer, restored (one ⌘Z back) or dropped after a confirmation
/// that says how much disk it frees.
struct StudioVersionsMenu: View {
  let model: StudioWorkspaceModel
  @Environment(\.undoManager) private var undoManager
  @Environment(\.locale) private var locale
  @State private var dropping: History.Version?

  var body: some View {
    let versions = model.versions
    Menu {
      ForEach(Array(versions.enumerated()), id: \.offset) { index, version in
        Menu {
          StudioVersionActions(model: model, index: index, version: version) { dropping = $0 }
        } label: {
          Text(verbatim: version.label)
        }
      }
    } label: {
      Text(.app("Versions (\(versions.count))"))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessible(.studioVersions, label: .app("Versions (\(versions.count))"))
    .confirmationDialog(
      Text(.app("Drop this version?")), isPresented: isAsking, presenting: dropping
    ) { version in
      Button(.app("Drop"), role: .destructive) {
        StudioUndo.dropVersion(model, version.id, on: undoManager)
      }
    } message: { version in
      Text(model.dropMessage(version.id, locale: locale))
    }
  }

  private var isAsking: Binding<Bool> {
    Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } })
  }
}

/// The actions on one version of the Versions menu (card 0159): Compare, Restore (one ⌘Z back),
/// Drop… (greyed with its reason; `onDrop` asks for the confirmation).
package struct StudioVersionActions: View {
  let model: StudioWorkspaceModel
  let index: Int
  let version: History.Version
  let onDrop: (History.Version) -> Void
  @Environment(\.undoManager) private var undoManager

  /// The actions on `version`, at `index` in the versions of `model`.
  package init(
    model: StudioWorkspaceModel, index: Int, version: History.Version,
    onDrop: @escaping (History.Version) -> Void
  ) {
    self.model = model
    self.index = index
    self.version = version
    self.onDrop = onDrop
  }

  package var body: some View {
    Button(.app("Compare")) { model.toggleCompare(version: version.id) }
      .accessible(.studioVersion(index, "compare"), label: .app("Compare"))
    Button(.app("Restore")) {
      StudioUndo.restoreVersion(model, version.id, on: undoManager)
    }
    .disabled(model.isMovingHistory)
    .accessible(.studioVersion(index, "restore"), label: .app("Restore"))
    let refusal = model.historyMoveRefusal ?? StudioUndo.dropRefusal(model, version.id)
    Button(.app("Drop…"), role: .destructive) { onDrop(version) }
      .disabled(refusal != nil)
      .help(refusal.map { Text($0) } ?? Text(verbatim: ""))
      .accessible(.studioVersion(index, "drop"), label: .app("Drop…"))
  }
}
