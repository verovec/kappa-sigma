internal import Observation
package import StackKit

/// The state of one master's disclosure on the Import sheet (card 0071).
///
/// Its statistics and warnings come from StackKit, with the other masters the role could take;
/// the user's choices (exclude, force, rebuild) go into the sheet's request. A warning never acts
/// on its own (R2).
@Observable
package final class MasterInspectViewModel {
  package let cell: ImportPlan.Cell
  package let channel: ImportPlan.Channel
  package private(set) var inspection: MasterInspection?
  /// The library masters this role could take, with the matcher's verdict on each (`load`).
  package private(set) var alternatives: [MasterAlternative] = []
  package private(set) var error: String?
  package private(set) var isWorking = false
  /// Siril's last percentage during a rebuild.
  package private(set) var progress: Int?
  /// What the last rebuild reported.
  package private(set) var notes: [String] = []
  /// Set when a rebuild would overwrite a library master: what would be lost, awaiting a yes.
  package private(set) var pendingReplace: String?

  private let sheet: ImportViewModel

  /// The disclosure of `cell` (a role of `channel`) on `sheet`.
  package init(cell: ImportPlan.Cell, channel: ImportPlan.Channel, sheet: ImportViewModel) {
    self.cell = cell
    self.channel = channel
    self.sheet = sheet
  }

  /// The library file behind the cell; `nil` for a master the capture would build, or a gap.
  package var path: String? {
    guard let path = cell.master?.path, !path.isEmpty else { return nil }
    return path
  }

  package var warnings: [MasterWarning] { inspection?.warnings ?? [] }

  /// Whether the user unchecked this master.
  package var isExcluded: Bool {
    if case .excluded = cell.status { true } else { false }
  }

  /// Whether the capture holds the frames this master stands for.
  package var canRebuild: Bool {
    sheet.masters != nil && sheet.plan?.sourceSet(of: cell) != nil
  }

  // MARK: - Actions

  /// Rates the alternatives and measures the library master, off the main actor.
  package func load() async {
    guard let plan = sheet.plan else { return }
    alternatives = await Self.alternatives(plan, cell: cell, channel: channel)
    guard let path, let masters = sheet.masters else { return }
    await work {
      self.inspection = try await masters.inspect(path)
    }
  }

  /// Unchecks this master (`calib_exclude`).
  package func exclude() { sheet.setIncluded(false, cell) }

  /// Checks it again.
  package func include() { sheet.setIncluded(true, cell) }

  /// Lets mismatched masters through (`force_calibration_frames`), for every light set: the
  /// legacy request has no per-set force.
  package func useForcedMatches() { sheet.setForceCalibration(true) }

  /// Opens the master in the viewer.
  package func preview() {
    guard let path else { return }
    sheet.masters?.preview(path)
  }

  /// Stacks the capture set this master stands for into the library, then plans again; over an
  /// existing library file it stops at `pendingReplace` until called with `replace`.
  package func rebuild(replace: Bool = false) async {
    guard let masters = sheet.masters, let plan = sheet.plan, let set = plan.sourceSet(of: cell)
    else { return }
    progress = nil
    pendingReplace = nil
    let (percents, sink) = AsyncStream.makeStream(of: Int.self)
    // One consumer, in order: no percentage lands after the build or out of sequence.
    let shown = Task { for await percent in percents { self.progress = percent } }
    let onLine: @Sendable (SirilLine) -> Void = { line in
      if let percent = line.percent { sink.yield(percent) }
    }
    await work {
      defer { sink.finish() }
      do {
        let result = try await masters.rebuild(
          set, plan.inventory, plan.library, replace, onLine)
        self.notes = result.warnings
        self.sheet.rescan()
      } catch CalibrationError.wouldReplace(let path, let frames) {
        self.pendingReplace =
          "replaces \(path)" + (frames > 0 ? " (\(frames) frames)" : "") + " in the library"
      }
    }
    await shown.value
  }

  private func work(_ body: () async throws -> Void) async {
    isWorking = true
    defer { isWorking = false }
    do {
      try await body()
      error = nil
    } catch {
      self.error = "\(error)"
    }
  }

  @concurrent
  private nonisolated static func alternatives(
    _ plan: ImportPlan, cell: ImportPlan.Cell, channel: ImportPlan.Channel
  ) async -> [MasterAlternative] {
    plan.alternatives(for: cell, of: channel)
  }
}
