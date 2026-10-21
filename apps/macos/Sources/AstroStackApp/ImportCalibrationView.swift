internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The calibration plan: what each light set gets per role, every gap, and why.
struct ImportCalibrationView: View {
  var model: ImportViewModel
  var plan: ImportPlan
  @Environment(\.locale) private var locale

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          isOn: Binding(
            get: { model.request.forceCalibration }, set: { model.setForceCalibration($0) })
        ) {
          Text(.app("Force these masters even when they do not match"))
        }
        ForEach(plan.calibration) { channel in channelView(channel) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.app("Calibration plan"))
    }
  }

  private func channelView(_ channel: ImportPlan.Channel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        verbatim: "\(channel.filter) · \(format.exposure(ms: channel.key.exposureMs)) · "
          + "\(ImportFormat.temperature(channel.key, in: format))"
          + (channel.key.session.isEmpty ? "" : " · \(channel.key.session)")
      )
      .font(.headline)
      ForEach(channel.cells) { cell in
        cellView(cell)
        if model.masters != nil && cell.master != nil {
          DisclosureGroup {
            MasterInspectView(
              model: MasterInspectViewModel(cell: cell, channel: channel, sheet: model)
            )
            // A new plan is a new disclosure: its @State model must not outlive the cell.
            .id("\(cell.suggestionID)|\(cell.master?.path ?? "")|\(cell.status)")
          } label: {
            Text(.app("Inspect \(role(cell))"))
          }
          .font(.caption)
        }
      }
      // StackKit's matcher notes, as it words them.
      ForEach(channel.notes, id: \.self) { note in
        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  /// A role: checked when applied, unchecked when the user excluded it; a gap cannot be checked.
  private func cellView(_ cell: ImportPlan.Cell) -> some View {
    Toggle(
      isOn: Binding(
        get: { Self.isApplied(cell.status) }, set: { model.setIncluded($0, cell) })
    ) {
      HStack(spacing: 0) {
        Text(verbatim: "\(role(cell)): ")
        Text(ImportFormat.status(cell.status))
      }
      .foregroundStyle(
        (cell.status == .missing ? DesignColor.statusAttention : DesignColor.textPrimary).color)
    }
    .disabled(cell.status == .missing)
  }

  private var format: AstroFormat { AstroFormat(locale: locale) }

  /// A master's role, worded as the frames it is stacked from (« Offsets »).
  private func role(_ cell: ImportPlan.Cell) -> String {
    AppGlossary.label(cell.role.frameType.termID, locale: locale)
  }

  static func isApplied(_ status: ImportPlan.Status) -> Bool {
    switch status {
    case .library, .build: true
    case .excluded, .missing: false
    }
  }
}
