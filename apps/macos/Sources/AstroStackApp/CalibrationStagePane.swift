internal import Foundation
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Calibration stage: for each light set of the last scan, the dark, flat and bias it gets —
/// the library file in full, or the frames the run builds it from — with the matcher's notes.
///
/// It shows the same scan as Données (the request a run applies, R2), so its sidebar state and
/// what it lists never disagree. Unchecking, forcing or rebuilding a master stays on the Import
/// sheet for now (0071), which the pane says.
struct CalibrationStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(DesignMetrics.spacingM)
      if let coverage = model.coverage {
        ScrollView {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
            ForEach(coverage.rows) { row in rowView(row, in: coverage) }
            Label(
              .app("To uncheck, force or rebuild a master, use Import Captures… on that night."),
              systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(DesignColor.textSecondary.color)
          }
          .padding([.horizontal, .bottom], DesignMetrics.spacingM)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else if model.nightPaths.isEmpty {
        EmptyState(
          .app("No capture night"),
          message: .app("Import a capture night to see the masters each light set gets."),
          systemImage: "square.stack.3d.down.right")
      } else if !model.isScanning {
        EmptyState(
          .app("Not scanned in this window"),
          message: .app(
            "Rescan reads the folders for their integration and calibration (~90 s a night)."),
          systemImage: "square.stack.3d.down.right")
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      SectionHeader(
        .app("Calibration masters"), detail: .app("What the next run applies to each light set."),
        help: StageHelp.help(.calibration, locale: locale))
      Spacer()
      if model.isScanning {
        ProgressView().controlSize(.small)
        Button(.app("Cancel")) { model.cancelScan() }
          .accessible(.calibrationCancelScan, label: .app("Cancel"))
      } else if !model.nightPaths.isEmpty {
        Button(.app("Rescan")) { model.rescan() }
          .accessible(.calibrationRescan, label: .app("Rescan"))
      }
    }
  }

  private func rowView(_ row: CoverageMatrix.Row, in coverage: CoverageMatrix) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
        ForEach(row.cells) { cell in cellView(cell) }
        // StackKit's matcher notes, as it words them; by position, two may read alike.
        ForEach(Array(row.notes.enumerated()), id: \.offset) { _, note in
          Label(note, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(DesignColor.textSecondary.color)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(verbatim: coverage.heading(row, locale: locale)).font(.headline)
    }
  }

  private func cellView(_ cell: ImportPlan.Cell) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingS) {
      Text(verbatim: AppGlossary.label(cell.role.frameType.termID, locale: locale))
        .frame(width: 90, alignment: .leading)
      StatusBadge(ImportFormat.badge(cell.status), ImportFormat.status(cell.status))
      if let path = ImportFormat.libraryPath(cell.status) {
        Text(verbatim: path)
          .font(.caption.monospaced())
          .foregroundStyle(DesignColor.textSecondary.color)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        Spacer()
        if model.masters != nil {
          Button(.app("Preview")) { model.previewMaster(path) }
            .controlSize(.small)
            .accessible(.calibrationPreview(cell.suggestionID), label: .app("Preview"))
        }
      }
    }
  }
}
