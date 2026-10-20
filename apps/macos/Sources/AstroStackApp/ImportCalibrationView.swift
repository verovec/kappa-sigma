internal import StackKit
internal import SwiftUI

/// The calibration plan: what each light set gets per role, every gap, and why.
struct ImportCalibrationView: View {
  var model: ImportViewModel
  var plan: ImportPlan

  var body: some View {
    GroupBox("Calibration plan") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "Force these masters even when they do not match",
          isOn: Binding(
            get: { model.request.forceCalibration }, set: { model.setForceCalibration($0) }))
        ForEach(plan.calibration) { channel in channelView(channel) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func channelView(_ channel: ImportPlan.Channel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        "\(channel.filter) · \(ImportFormat.exposure(channel.key.exposureMs)) · "
          + "\(ImportFormat.temperature(channel.key))"
          + (channel.key.session.isEmpty ? "" : " · \(channel.key.session)")
      )
      .font(.headline)
      ForEach(channel.cells) { cell in cellView(cell) }
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
      Text("\(cell.role.rawValue): \(ImportFormat.status(cell.status))")
        .foregroundStyle(cell.status == .missing ? Color.orange : Color.primary)
    }
    .disabled(cell.status == .missing)
  }

  static func isApplied(_ status: ImportPlan.Status) -> Bool {
    switch status {
    case .library, .build: true
    case .excluded, .missing: false
    }
  }
}
