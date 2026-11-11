internal import ProjectKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Données stage: the project's capture nights, what they hold (integration per filter ×
/// night) and how each light set is calibrated (0078), the Import sheet that adds nights, and
/// what the stacks take on disk (0114).
struct DataStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    if model.sources.isEmpty {
      // The stage's « ? » is there before the first night too.
      EmptyState(
        .app("Empty project"),
        message: .app("Import a capture night to see how it will be calibrated and stacked."),
        systemImage: "sparkles", help: StageHelp.help(.data, locale: locale)
      ) {
        Button(.app("Import Captures…")) { model.startImport() }
          .accessible(.importCaptures, label: .app("Import Captures…"))
      }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
          header
          ForEach(model.sources, id: \.id) { source in
            sourceRow(source)
          }
          scanned
          if !model.stacks.isEmpty {
            Divider()
            StackStorageView(model: model)
          }
        }
        .padding(DesignMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// One source's row: a folder of this Mac, or a bucket prefix (card 0169).
  ///
  /// A remote row shows what its last scan answered and why the last one failed, if it did; a
  /// failure never replaces the count, since an empty inventory would read as « the prefix holds
  /// nothing » (R2).
  @ViewBuilder private func sourceRow(_ source: ProjectSource) -> some View {
    if source.kind == .remoteNight {
      let state = model.remoteState(of: source.path)
      VStack(alignment: .leading, spacing: 2) {
        Label(source.path, systemImage: "externaldrive.badge.icloud").font(.caption)
        if let lights = state?.lights {
          Text(.app("\(lights) lights read in place")).font(.caption2).foregroundStyle(.secondary)
        }
        if state?.isScanning == true {
          // The last failure waits for this read's answer: shown beside it, it would read as
          // the current state; a cancelled read shows it again.
          Text(.app("Scanning…")).font(.caption2).foregroundStyle(.secondary)
        } else if let failure = state?.failure {
          // Its own words: `S3Error` already starts with « S3 », and a missing connection names
          // Settings — prefixing either would read « S3: S3 403 … ».
          StatusBadge(.error, failure.message)
        }
      }
    } else {
      Label(source.path, systemImage: "folder").font(.caption)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      SectionHeader(
        .app("Capture nights"), detail: .app("Read, never written."),
        help: StageHelp.help(.data, locale: locale))
      Spacer()
      // A bucket read in flight is a scan too (card 0182): Cancel stops it.
      if model.isScanning || model.isScanningRemote {
        ProgressView().controlSize(.small)
        Button(.app("Cancel")) { model.cancelScan() }
          .accessible(.dataCancelScan, label: .app("Cancel"))
      } else if !model.nightPaths.isEmpty {
        // A legacy run alone is a source, never a capture: nothing to rescan.
        Button(.app("Rescan")) { model.rescan() }
          .accessible(.dataRescan, label: .app("Rescan"))
      }
      Button(.app("Import Captures…")) { model.startImport() }
        .accessible(.importCaptures, label: .app("Import Captures…"))
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
      // A remote scan's frames whose pixel checks were not run (card 0167): said, never passed.
      if let unchecked = model.scan?.inventory.notCheckedRemotely, !unchecked.isEmpty {
        Label(
          RemoteObjectStore.notCheckedWords(unchecked.count), systemImage: "icloud.slash"
        )
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
