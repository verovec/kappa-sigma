internal import RenderKit
internal import SwiftUI

/// The Données stage: the project's capture nights, what they hold (integration per filter ×
/// night) and how each light set is calibrated (0078), and the Import sheet that adds nights.
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
      }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
          header
          ForEach(model.sources, id: \.id) { source in
            Label(source.path, systemImage: "folder").font(.caption)
          }
          scanned
        }
        .padding(DesignMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      SectionHeader(.app("Capture nights"), detail: .app("Read, never written."))
      Spacer()
      if model.isScanning {
        ProgressView().controlSize(.small)
        Button(.app("Cancel")) { model.cancelScan() }
      } else if !model.nightPaths.isEmpty {
        // A legacy run alone is a source, never a capture: nothing to rescan.
        Button(.app("Rescan")) { model.rescan() }
      }
      Button(.app("Import Captures…")) { model.startImport() }
    }
  }

  @ViewBuilder private var scanned: some View {
    if let integration = model.integration, let coverage = model.coverage {
      DataIntegrationView(summary: integration)
      Divider()
      DataCoverageView(coverage: coverage) { model.select(.calibration) }
      // The scan's own warnings, as StackKit words them.
      ForEach(Array((model.scan?.warnings ?? []).enumerated()), id: \.offset) { _, warning in
        Label(warning, systemImage: "exclamationmark.triangle")
          .foregroundStyle(DesignColor.statusAttention.color)
      }
    } else if !model.isScanning && !model.nightPaths.isEmpty {
      EmptyState(
        .app("Not scanned in this window"),
        message: .app(
          "Rescan reads the folders for their integration and calibration (~90 s a night)."),
        systemImage: "magnifyingglass")
    }
  }
}
