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
      // StackKit's warnings and rebuild notes, as it words them.
      ForEach(model.warnings, id: \.kind) { warning in
        Label(warning.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      if let error = model.error { Text(error.message).foregroundStyle(.red) }
      alternatives
      actions
      if let pending = model.pendingReplace {
        Label {
          Text(.app("Rebuilding \(pending): confirm with Replace"))
        } icon: {
          Image(systemName: "exclamationmark.circle")
        }
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
      let built = inspection.builtAt.formatted(date: .abbreviated, time: .shortened)
      let frames = ImportFormat.frames(inspection.frames)
      Text(.app("\(inspection.width)×\(inspection.height) · \(frames) · built \(built)"))
      let (median, madn) = (MasterFormat.value(stats.median), MasterFormat.value(stats.madn))
      let (low, high) = (MasterFormat.value(stats.min), MasterFormat.value(stats.max))
      Text(.app("median \(median) · σ (MAD) \(madn) · min \(low) · max \(high)"))
      let quadrants = stats.quadrantMedians.map(MasterFormat.value).joined(separator: " / ")
      Text(.app("quadrants \(quadrants)"))
      if let vignetting = stats.vignettingPct {
        Text(.app("corners vs centre \(MasterFormat.percent(vignetting))"))
      }
      Text(.app("clipped \(MasterFormat.percent(stats.clippedPct))"))
      if let hot = stats.hotPixels { Text(.app("hot pixels \(hot)")) }
    }
    .font(.caption.monospacedDigit())
  }

  @ViewBuilder
  private var alternatives: some View {
    let others = model.alternatives.filter { $0.verdict != .chosen }
    if !others.isEmpty {
      Text(.app("Other masters for this role")).font(.caption.bold())
      ForEach(others) { alternative in
        let name = MasterFormat.name(alternative.master.path)
        Text(.app("\(name) — \(MasterFormat.verdict(alternative.verdict))"))
          .font(.caption)
          .foregroundStyle(alternative.verdict == .matches ? Color.primary : Color.secondary)
      }
    }
  }

  private var actions: some View {
    HStack {
      if model.path != nil { Button(.app("Preview")) { model.preview() } }
      if model.isExcluded {
        Button(.app("Include")) { model.include() }
      } else {
        Button(.app("Exclude")) { model.exclude() }
      }
      if model.alternatives.contains(where: { $0.verdict == .needsForce }) {
        Button(.app("Use forced matches")) { model.useForcedMatches() }
          .help(Text(.app("Lets every mismatched master through, for all light sets")))
      }
      if model.canRebuild {
        Button(.app("Rebuild from the capture")) { Task { await model.rebuild() } }
      }
      if let pending = model.pendingReplace {
        Button(.app("Replace")) { Task { await model.rebuild(replace: true) } }
          .help(Text(pending))
      }
      if model.isWorking {
        ProgressView().controlSize(.small)
        if let progress = model.progress { Text(verbatim: "\(progress) %").monospacedDigit() }
      }
    }
    .disabled(model.isWorking)
  }
}
