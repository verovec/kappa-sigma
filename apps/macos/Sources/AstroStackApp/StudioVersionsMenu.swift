internal import ProcessKit
internal import RenderKit
internal import SwiftUI

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
          Button(.app("Compare")) { model.toggleCompare(version: version.id) }
            .accessible(.studioVersion(index, "compare"), label: .app("Compare"))
          Button(.app("Restore")) {
            StudioUndo.restoreVersion(model, version.id, on: undoManager)
          }
          .disabled(model.isMovingHistory)
          .accessible(.studioVersion(index, "restore"), label: .app("Restore"))
          Button(.app("Drop…"), role: .destructive) { dropping = version }
            .disabled(model.isMovingHistory)
            .accessible(.studioVersion(index, "drop"), label: .app("Drop…"))
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
      let size = AstroFormat(locale: locale).bytes(Int64(model.bytes(ofVersion: version.id)))
      Text(.app("Its steps and their files are deleted (\(size)). This cannot be undone."))
    }
  }

  private var isAsking: Binding<Bool> {
    Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } })
  }
}
