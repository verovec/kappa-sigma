package import Foundation
package import ImageKit
internal import Metal
internal import Observation
package import ProcessKit
package import ProjectKit
internal import RenderKit

/// The Studio's working image of one stack (card 0087): a history whose step 0 is the channel
/// combination, mirrored in the project (one `studio` image, a row per step, its head).
///
/// The history's files are the images; the rows only mirror them for the summary and the disk
/// budget. Reopening the project reopens the history from its folder.
@Observable
package final class StudioModel {
  /// The processing (history, bundle, GPU).
  @ObservationIgnored package let session: StudioSession
  /// The applied steps, oldest first.
  package private(set) var steps: [History.Step] = []
  /// The working image: the history's head.
  package private(set) var head: AstroImage

  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private let imageID: Int64
  @ObservationIgnored private let packageRoot: URL

  /// The Studio of stack `stackID` whose files are in `stackFolder`, over `bundle`; a fresh
  /// history starts with the channel combination of `combination` (the kept profile's values),
  /// else its defaults — a step like any other, never hidden (R2).
  package init(
    store: ProjectStore, stackID: Int64, stackFolder: URL, bundle: PipelineBundle,
    combination: ParamSet? = nil, registry: ProcessRegistry? = nil
  ) throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
    let registry = try registry ?? ProcessRegistry.standard()
    guard let base = bundle.layers["RGB"] ?? bundle.layers.values.first else {
      throw StudioError.emptyBundle
    }
    let history = try History.reopen(
      directory: stackFolder.appendingPathComponent("history"), original: base
    ) { registry.type(id: $0)?.schema }
    session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device)
    self.store = store
    packageRoot = stackFolder.deletingLastPathComponent().deletingLastPathComponent()
    let images = try store.images(stackID: stackID)
    imageID =
      try images.first { $0.role == Self.imageRole }?.id
      ?? store.addImage(stackID: stackID, role: Self.imageRole).id
    head = history.current
    if history.steps.isEmpty && !history.canRedo {
      let params = combination ?? ParamSet(schema: ChannelCombinationProcess.schema)
      try apply(ChannelCombinationProcess.id, params: params)
    }
    steps = history.steps
  }

  /// The project image the Studio's history is mirrored on.
  package static let imageRole = "studio"

  /// Applies `processID` with `params` (under `mask`) to the head.
  package func apply(_ processID: String, params: ParamSet, mask: AstroImage? = nil) throws {
    try dropUndone()
    try session.apply(processID, params: params, mask: mask)
    try mirrorApplied()
  }

  /// Records a step made elsewhere (a host tool) with the layers it wrote.
  package func apply(
    _ processID: String, params: ParamSet, result: AstroImage,
    outputs: [LayerRole: AstroImage] = [:]
  ) throws {
    try dropUndone()
    try session.apply(processID, params: params, result: result, outputs: outputs)
    try mirrorApplied()
  }

  /// What `processID` with `params` makes of the head at `scale` (the live preview; at scale 1
  /// it is the pixels Apply records), under `mask`.
  package func preview(
    _ processID: String, params: ParamSet, scale: Double = 1, mask: AstroImage? = nil
  ) throws -> AstroImage {
    try session.render(processID, params: params, scale: scale, purpose: .preview, mask: mask)
  }

  /// Back one step.
  package func undo() throws {
    try session.history.undo()
    try mirrorHead()
  }

  /// Forward one undone step.
  package func redo() throws {
    try session.history.redo()
    try mirrorHead()
  }

  /// Whether a step can be undone (step 0 included: back to the base layer).
  package var canUndo: Bool { !steps.isEmpty }
  /// Whether an undone step can be redone.
  package var canRedo: Bool { session.history.canRedo }

  /// The mirrored rows, oldest first: the applied steps, then the undone ones in redo order.
  private func rows() throws -> [HistoryStep] {
    try store.history(imageID: imageID)
  }

  /// A new step drops the undone ones: their rows go (the files go at the next save).
  private func dropUndone() throws {
    let applied = session.history.steps.count
    for row in try rows().dropFirst(applied) { try store.deleteHistoryStep(id: row.id) }
  }

  private func mirrorApplied() throws {
    let history = session.history
    guard let step = history.steps.last else { return }
    let url = history.directory.appendingPathComponent(step.file)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    let json = String(bytes: try JSONEncoder().encode(step.params), encoding: .utf8) ?? "[]"
    let path = String(url.path.dropFirst(packageRoot.path.count + 1))
    try store.appendHistoryStep(
      imageID: imageID, processID: step.processID, paramsJSON: json,
      output: HistoryStep.Output(path: path, bytes: Int64(bytes)), contentHash: nil)
    refresh()
  }

  private func mirrorHead() throws {
    let applied = session.history.steps.count
    let rows = try rows()
    try store.setHead(imageID: imageID, stepID: applied > 0 ? rows[applied - 1].id : nil)
    refresh()
  }

  private func refresh() {
    steps = session.history.steps
    head = session.history.current
  }
}
