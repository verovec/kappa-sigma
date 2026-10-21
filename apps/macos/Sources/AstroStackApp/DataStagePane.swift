internal import RenderKit
internal import SwiftUI

/// The Données stage: the project's capture nights, and the Import sheet that adds them.
struct DataStagePane: View {
  var model: ProjectWindowModel

  var body: some View {
    if model.sources.isEmpty {
      ContentUnavailableView {
        Label {
          Text(.app("Empty project"))
        } icon: {
          Image(systemName: "sparkles")
        }
      } description: {
        Text(.app("Import a capture night to see how it will be calibrated and stacked."))
      } actions: {
        Button(.app("Import Captures…")) { model.startImport() }
          .accessible(.importCaptures, label: .app("Import Captures…"))
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          SectionHeader(.app("Capture nights"), detail: .app("Read, never written."))
          Spacer()
          Button(.app("Import Captures…")) { model.startImport() }
            .accessible(.importCaptures, label: .app("Import Captures…"))
        }
        .padding(DesignMetrics.spacingM)
        List(model.sources, id: \.id) { source in
          Label(source.path, systemImage: "folder")
        }
      }
    }
  }
}
