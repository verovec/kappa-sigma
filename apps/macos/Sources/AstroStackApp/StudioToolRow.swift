internal import ProcessKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// Under the panel of a host-tool process (card 0093): the run in progress with its last line
/// and Stop, then what the tool reported.
struct StudioToolRow: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  var body: some View {
    if let run = model.toolRun {
      HStack {
        ProgressView().controlSize(.small)
        Text(verbatim: run.line).font(.caption).lineLimit(1).truncationMode(.middle)
        Spacer()
        Button(.app("Stop")) { model.cancelTool() }
          .accessible(.studioToolStop, label: .app("Stop"))
      }
    } else if let report = model.toolReport {
      StatusBadge(.ok, report(locale))
    }
  }
}
