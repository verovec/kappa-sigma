internal import StackKit
package import SwiftUI

/// The disclosure of one calibration master: what its pixels say, the thresholds crossed, the
/// other masters the role could take, and the user's choices (card 0071).
package struct MasterInspectView: View {
  @State var model: MasterInspectViewModel

  /// The disclosure of the master behind `model`.
  package init(model: MasterInspectViewModel) {
    _model = State(initialValue: model)
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let inspection = model.inspection { stats(inspection) }
      ForEach(model.warnings, id: \.kind) { warning in
        Label(warning.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      if let error = model.error { Text(error).foregroundStyle(.red) }
      alternatives
      actions
      if let pending = model.pendingReplace {
        Label("Rebuilding \(pending): confirm with Replace", systemImage: "exclamationmark.circle")
          .font(.caption)
      }
      ForEach(model.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
    }
    .padding(.leading, 20)
    .task { await model.load() }
  }

  private func stats(_ inspection: MasterInspection) -> some View {
    let stats = inspection.stats
    return VStack(alignment: .leading, spacing: 2) {
      Text(
        "\(inspection.width)×\(inspection.height) · \(inspection.frames) frames · built "
          + inspection.builtAt.formatted(date: .abbreviated, time: .shortened))
      Text(
        "median \(MasterFormat.value(stats.median)) · σ (MAD) \(MasterFormat.value(stats.madn)) · "
          + "min \(MasterFormat.value(stats.min)) · max \(MasterFormat.value(stats.max))")
      Text("quadrants " + stats.quadrantMedians.map(MasterFormat.value).joined(separator: " / "))
      if let vignetting = stats.vignettingPct {
        Text("corners vs centre \(MasterFormat.percent(vignetting))")
      }
      Text("clipped \(MasterFormat.percent(stats.clippedPct))")
      if let hot = stats.hotPixels { Text("hot pixels \(hot)") }
    }
    .font(.caption.monospacedDigit())
  }

  @ViewBuilder
  private var alternatives: some View {
    let others = model.alternatives.filter { $0.verdict != .chosen }
    if !others.isEmpty {
      Text("Other masters for this role").font(.caption.bold())
      ForEach(others) { alternative in
        Text(
          "\(MasterFormat.name(alternative.master.path)) — "
            + MasterFormat.verdict(alternative.verdict)
        )
        .font(.caption)
        .foregroundStyle(alternative.verdict == .matches ? Color.primary : Color.secondary)
      }
    }
  }

  private var actions: some View {
    HStack {
      if model.path != nil { Button("Preview") { model.preview() } }
      if model.isExcluded {
        Button("Include") { model.include() }
      } else {
        Button("Exclude") { model.exclude() }
      }
      if model.alternatives.contains(where: { $0.verdict == .needsForce }) {
        Button("Use forced matches") { model.useForcedMatches() }
          .help("Lets every mismatched master through, for all light sets")
      }
      if model.canRebuild {
        Button("Rebuild from the capture") { Task { await model.rebuild() } }
      }
      if let pending = model.pendingReplace {
        Button("Replace") { Task { await model.rebuild(replace: true) } }
          .help(pending)
      }
      if model.isWorking {
        ProgressView().controlSize(.small)
        if let progress = model.progress { Text("\(progress) %").monospacedDigit() }
      }
    }
    .disabled(model.isWorking)
  }
}
