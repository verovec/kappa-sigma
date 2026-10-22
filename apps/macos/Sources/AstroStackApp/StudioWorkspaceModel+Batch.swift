package import Foundation
internal import ImageKit
internal import ProcessKit
package import StackKit

/// Background extraction in the Studio (card 0092) on the host-tool seam of card 0093: an
/// engine whose tool is missing greys its option with the reason and refuses Apply before any
/// tool runs, never replaced by another engine (R2); the model the extraction removed can be
/// shown in the viewer.
extension StudioWorkspaceModel {
  /// What the Studio knows of the host tools behind an engine choice, and the model view.
  package struct BatchState {
    /// The viewer shows the background model instead of the head.
    package var showsModel = false
    /// Where each host tool stood when last probed.
    package var statuses: [HostTool: ToolStatus] = [:]
  }

  /// The viewer shows the background model.
  package var showsModel: Bool { batch.showsModel }

  /// The tool the panel's values need and the last probe did not find, with its status.
  package var missingTool: (tool: HostTool, status: ToolStatus)? {
    guard let panel,
      let tool = BackgroundExtractionTool.host(for: panel.type.id, params: panel.params),
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

  /// A process was chosen: the tools behind its options are probed.
  func toolsChosen() {
    guard panel?.type.id == BackgroundExtractionProcess.id else { return }
    Task { [weak self] in await self?.refreshTools() }
  }

  /// Probes the tools of background extraction's engines and greys each option whose tool is
  /// missing, with the reason; the values stay as the user set them (R2).
  package func refreshTools() async {
    guard let panel, panel.type.id == BackgroundExtractionProcess.id else { return }
    for tool in Set(BackgroundExtractionProcess.engines.map(BackgroundExtractionTool.host(engine:)))
    {
      batch.statuses[tool] = await locate(tool)
    }
    var reasons: [String: LocalizedStringResource] = [:]
    for engine in BackgroundExtractionProcess.engines {
      let tool = BackgroundExtractionTool.host(engine: engine)
      if let status = batch.statuses[tool], let reason = Self.reason(tool, status) {
        reasons[engine] = reason
      }
    }
    panel.unavailableOptions["engine"] = reasons
    greyUnavailable()
  }

  /// Greys what the current values cannot run: dividing with a Siril engine.
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

  /// Why the panel's host tool must not run with its values, checked just before it would: the
  /// tool its engine needs probed again (installed meanwhile, or removed), the correction its
  /// engine applies. `nil`: it may run.
  func preflight(_ processID: String, params: ParamSet) async -> LocalizedStringResource? {
    guard processID == BackgroundExtractionProcess.id else { return nil }
    if let reason = Self.correctionReason(params) { return reason }
    guard let tool = BackgroundExtractionTool.host(for: processID, params: params) else {
      return nil
    }
    let status = await locate(tool)
    batch.statuses[tool] = status
    return Self.reason(tool, status)
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
    guard
      let model = try studio.session.history.writtenLayer(LayerRole.backgroundModel.rawValue)
    else { return }
    try show(model)
    batch.showsModel = true
  }

  /// The toggle's click: a model that cannot be shown says why, as a compare does.
  package func toggleModelReported() {
    do {
      try toggleModel()
    } catch {
      failure = UserFacingError(error).message
    }
  }

  /// The model view goes: the viewer shows the head again.
  func hideModel() {
    guard batch.showsModel else { return }
    batch.showsModel = false
    try? show(studio.head)
  }
}
