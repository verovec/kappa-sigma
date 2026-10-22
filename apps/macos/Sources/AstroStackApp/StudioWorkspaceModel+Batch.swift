package import Foundation
internal import ImageKit
package import ProcessKit
package import StackKit

/// Batch processes in the Studio (card 0092, design §4.6): their host tool runs on Apply and its
/// result is the preview; a missing tool greys its option with the reason and refuses the run,
/// never replaced by another engine (R2); the model a background extraction removed can be shown
/// in the viewer.
extension StudioWorkspaceModel {
  /// The batch side of the workspace.
  package struct BatchState {
    /// The run's progress, 0…1, while a batch process runs; `nil` otherwise.
    package var progress: Double?
    /// The viewer shows the background model instead of the head.
    package var showsModel = false
    /// Where each host tool stood when last probed.
    package var statuses: [HostTool: ToolStatus] = [:]
    /// The run started by Apply (cancelled when the workspace is retired).
    var task: Task<Void, Never>?
  }

  /// The running batch process's progress (`nil`: none runs).
  package var batchProgress: Double? { batch.progress }
  /// The viewer shows the background model.
  package var showsModel: Bool { batch.showsModel }
  /// The run Apply started, if it is still going.
  package var batchTask: Task<Void, Never>? { batch.task }

  /// The tool the panel's values need and the last probe did not find, with its status.
  package var missingTool: (tool: HostTool, status: ToolStatus)? {
    guard let panel, let tool = StudioTools.tool(for: panel.type.id, params: panel.params),
      let status = batch.statuses[tool], !status.isUsable
    else { return nil }
    return (tool, status)
  }

  /// Why `tool` cannot run at `status`, or `nil` when it can.
  package static func reason(_ tool: HostTool, _ status: ToolStatus) -> LocalizedStringResource? {
    switch status {
    case .found: nil
    case .missing(let path): .app("\(tool.productName) is not installed at \(path).")
    case .tooOld(_, let version): UserFacingError.siril(.tooOld(version: version)).message
    }
  }

  /// A new temporary folder for the extraction's work files and cached pairs.
  ///
  /// Never the project package (full-size pairs per request would grow it past its disk budget)
  /// nor `output/`. Made once, by the workspace's initialiser (`tools.scratch`), and removed when
  /// the workspace is retired, so a later workspace of the same stack never shares it.
  static func newScratch() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Background/" + UUID().uuidString, isDirectory: true)
  }

  /// Starts the panel's batch process (Apply), calling `recorded` when it ends; one at a time.
  package func startBatch(recorded: @escaping () -> Void = {}) {
    guard batch.task == nil, batch.progress == nil else { return }
    batch.task = Task { [weak self] in
      let applied = await self?.runBatch() ?? false
      guard let self else { return }
      batch.task = nil
      // Only the step this run recorded registers a move (never one a cancelled or refused
      // run left to another).
      if applied, !Task.isCancelled, !isRetired { recorded() }
    }
  }

  /// An undo or redo during a tool run: the run Apply started is cancelled (it records
  /// nothing) and the move goes ahead, so ⌘Z never loses its entry; a run without a task to
  /// cancel refuses the move with the reason.
  func stopBatchForHistory() throws {
    guard batch.task != nil || batch.progress != nil else { return }
    if let task = batch.task {
      task.cancel()
      return
    }
    failure = UserFacingError(StudioError.toolRunning).message
    throw StudioError.toolRunning
  }

  /// Removes the extraction's work files and cached pairs (the workspace is replaced) once
  /// `run` has ended, off the main actor (gigabytes of FITS pairs).
  func clearScratch(after run: Task<Void, Never>?) {
    guard let scratch = tools.scratch else { return }
    Task {
      await run?.value
      await Self.remove(scratch)
    }
  }

  @concurrent
  private nonisolated static func remove(_ folder: URL) async {
    try? FileManager.default.removeItem(at: folder)
  }

  /// The model view goes: the viewer shows the head again.
  func hideModel() {
    guard batch.showsModel else { return }
    batch.showsModel = false
    try? show(studio.head)
  }

  /// A batch process was chosen: its tools are probed.
  func batchChosen() {
    Task { [weak self] in await self?.refreshTools() }
  }

  /// Probes the tools of the panel's batch process and greys each option whose tool is
  /// missing, with the reason; the values stay as the user set them (R2).
  package func refreshTools() async {
    guard let panel, panel.type.id == BackgroundExtractionProcess.id else { return }
    var reasons: [String: LocalizedStringResource] = [:]
    for tool in Set(BackgroundExtractionProcess.engines.map(StudioTools.tool(engine:))) {
      batch.statuses[tool] = await tools.locate(tool)
    }
    for engine in BackgroundExtractionProcess.engines {
      let tool = StudioTools.tool(engine: engine)
      if let status = batch.statuses[tool], let reason = Self.reason(tool, status) {
        reasons[engine] = reason
      }
    }
    panel.unavailableOptions["engine"] = reasons
    greyUnavailable()
  }

  /// Greys what the current values cannot run: dividing with a Siril engine (its `subsky` only
  /// subtracts).
  func greyUnavailable() {
    guard let panel, panel.type.id == BackgroundExtractionProcess.id else { return }
    panel.unavailableOptions["correction"] =
      Self.correctionReason(panel.params).map { ["divide": $0] } ?? [:]
  }

  /// Why the values ask a correction their engine cannot apply, or `nil`.
  static func correctionReason(_ params: ParamSet) -> LocalizedStringResource? {
    // StackKit's own rule, shown before a run.
    BackgroundEngine(params: params).supports(BackgroundCorrection(params: params))
      ? nil : .app("Siril's subsky only subtracts: dividing needs GraXpert.")
  }

  /// Applies the panel's batch process: its tool is probed first (missing: the run is refused
  /// with the reason, nothing else runs), then the tool runs with its progress shown and the
  /// step is recorded; the head is shown.
  @discardableResult
  package func runBatch() async -> Bool {
    guard let panel, panel.type.isBatch, batch.progress == nil else { return false }
    guard pipeline?.isRunning != true else {
      failure = UserFacingError(StudioError.toolRunning).message
      return false
    }
    let params = panel.params
    // Marked running before the probe: a second Apply meanwhile finds it busy.
    batch.progress = 0
    defer { batch.progress = nil }
    if let reason = Self.correctionReason(params) {
      failure = reason
      return false
    }
    if let tool = StudioTools.tool(for: panel.type.id, params: params) {
      let status = await tools.locate(tool)
      batch.statuses[tool] = status
      if let reason = Self.reason(tool, status) {
        failure = reason
        return false
      }
    }
    // Cancelled during the probe (an undo): no tool is started.
    guard !Task.isCancelled else { return false }
    guard let process = batchProcesses[panel.type.id] else {
      failure = UserFacingError(StudioError.unknownProcess(panel.type.id)).message
      return false
    }
    do {
      try await studio.apply(panel.type.id, batch: process, params: params) { [weak self] value in
        Task { @MainActor in
          // A late report after the run ended draws no progress row.
          if self?.batch.progress != nil { self?.batch.progress = value }
        }
      }
      failure = nil
      // The user's manual work becomes the recipe (R5), as a GPU Apply.
      pipeline?.applied(panel.type.id, params: params)
      try headChanged()
      return true
    } catch  where Task.isCancelled {
      // Cancelled by an undo or a retired workspace (whatever the tool's teardown threw):
      // nothing to report, and the undo's own outcome stays shown.
    } catch {
      failure = UserFacingError(error).message
    }
    return false
  }

  /// Whether a background model is in the context (a background extraction was applied).
  package var canShowModel: Bool {
    studio.session.layerIDs().contains(LayerRole.backgroundModel.rawValue)
  }

  /// Shows the latest background model in the viewer (its own display stretch), or the head
  /// again.
  package func toggleModel() throws {
    if batch.showsModel {
      batch.showsModel = false
      try show(studio.head)
      return
    }
    guard let model = try studio.session.history.writtenLayers()[LayerRole.backgroundModel.rawValue]
    else { return }
    try show(model)
    batch.showsModel = true
  }

  /// The batch processes by id, over this workspace's tools: its Apply and its pipeline's runs
  /// run the same.
  package var batchProcesses: [String: PipelineRunner.BatchProcess] {
    [BackgroundExtractionProcess.id: BackgroundExtractionProcess.batch(tools.background)]
  }
}
