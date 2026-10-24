package import Foundation
package import ImageKit
internal import Metal
internal import OSLog
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
  /// The stack's header (its base layer's): where suggestions read pointing and optics.
  @ObservationIgnored package let header: FITSHeader?

  @ObservationIgnored private let store: ProjectStore
  /// The project image (role `studio`) the history is mirrored on.
  @ObservationIgnored package let imageID: Int64
  @ObservationIgnored private let packageRoot: URL

  /// The Studio of stack `stackID` over `bundle`.
  ///
  /// Its files are in `stackFolder` inside the project package `packageFolder`; its outputs keep
  /// `header`'s descriptive cards. A fresh history starts with the channel combination of
  /// `combination` (the kept profile's values), else its defaults — a step like any other, never
  /// hidden (R2).
  package init(
    store: ProjectStore, stackID: Int64, packageFolder: URL, stackFolder: URL,
    bundle: PipelineBundle, header: FITSHeader? = nil, combination: ParamSet? = nil,
    registry: ProcessRegistry? = nil
  ) throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noDevice }
    let registry = try registry ?? ProcessRegistry.standard()
    guard let baseID = StudioSession.baseLayerID(bundle.layers.keys),
      let base = bundle.layers[baseID]
    else { throw StudioError.emptyBundle }
    // Every step keeps the stack's descriptive cards (WCS, OBJECT…).
    let history = try History.reopen(
      directory: stackFolder.appendingPathComponent("history"), original: base, header: header,
      movesPixels: registry.movesPixels
    ) { registry.type(id: $0)?.schema ?? Self.batchSchemas[$0] }
    session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device)
    self.store = store
    self.header = header
    packageRoot = packageFolder
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

  /// The schemas of the host-tool steps a history may hold (not in the registry: no shader).
  package static let batchSchemas = [StarSeparation.id: StarSeparation.schema]

  /// Applies `processID` with `params` (under `mask`) to the head.
  package func apply(_ processID: String, params: ParamSet, mask: AstroImage? = nil) throws {
    defer { mirror() }
    try session.apply(processID, params: params, mask: mask)
    cleanUp()
  }

  /// Records a step made elsewhere (a host tool) with the layers it wrote.
  package func apply(
    _ processID: String, params: ParamSet, result: AstroImage,
    outputs: [LayerRole: AstroImage] = [:], replacing: [String: AstroImage] = [:]
  ) throws {
    defer { mirror() }
    try session.apply(
      processID, params: params, result: result, outputs: outputs, replacing: replacing)
    cleanUp()
  }

  /// Runs the host tool `batch` as the step `id` on the head, its progress (0…1) to
  /// `onProgress`; nothing is recorded when it fails or is cancelled.
  package func apply(
    _ batch: PipelineRunner.BatchProcess, id: String, params: ParamSet,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    defer { mirror() }
    try await session.apply(batch, id: id, params: params, onProgress: onProgress)
    cleanUp()
  }

  /// What `processID` with `params` makes of the head at `scale` (the live preview; at scale 1
  /// it is the pixels Apply records), under `mask`.
  package func preview(_ processID: String, params: ParamSet, mask: AstroImage? = nil) throws
    -> AstroImage
  {
    try session.render(processID, params: params, purpose: .preview, mask: mask)
  }

  /// Runs `move` on the history (a pipeline run, card 0088), then records what it applied in
  /// the project, whether it finished or failed.
  package func moving<Result>(_ move: (History) async throws -> Result) async throws -> Result {
    defer { mirror() }
    let result = try await move(session.history)
    cleanUp()
    return result
  }

  /// Back one step.
  package func undo() throws {
    defer { mirror() }
    try session.history.undo()
  }

  /// Forward one undone step.
  package func redo() throws {
    defer { mirror() }
    try session.history.redo()
  }

  /// Whether a step can be undone (step 0 included: back to the base layer).
  package var canUndo: Bool { !steps.isEmpty }
  /// Whether an undone step can be redone.
  package var canRedo: Bool { session.history.canRedo }

  /// Brings the project's rows in line with the history, whatever happened.
  ///
  /// A failed apply or a manifest that could not be written leaves nothing behind: one row per
  /// kept step, matched by its output file (never by position), the head on the last applied.
  private func mirror() {
    defer { refresh() }
    do {
      let history = session.history
      let kept = history.steps + history.undone.reversed()
      var rows = try store.history(imageID: imageID)
      let wanted = Set(kept.map { path(of: $0.file) })
      for row in rows where !wanted.contains(row.outputPath ?? "") {
        try store.deleteHistoryStep(id: row.id)
      }
      rows = rows.filter { wanted.contains($0.outputPath ?? "") }
      for step in kept where !rows.contains(where: { $0.outputPath == path(of: step.file) }) {
        rows.append(try appendRow(step))
      }
      let head = history.steps.last.flatMap { last in
        rows.first { $0.outputPath == path(of: last.file) }?.id
      }
      try store.setHead(imageID: imageID, stepID: head)
    } catch {
      // The rows only mirror the history (its files are the truth): a failed write is retried
      // by the next move.
      Self.logger.error("history mirror: \(String(describing: error), privacy: .public)")
    }
  }

  private func path(of file: String) -> String {
    let url = session.history.directory.appendingPathComponent(file)
    return String(url.path.dropFirst(packageRoot.path.count + 1))
  }

  private func appendRow(_ step: History.Step) throws -> HistoryStep {
    // The step's image and the layers it wrote or rewrote: what the disk budget counts.
    let files = [step.file] + step.outputs.values + step.replaced.values
    let bytes = files.reduce(0) { total, file in
      let url = session.history.directory.appendingPathComponent(file)
      let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
      return total + (size ?? 0)
    }
    let json = String(bytes: try JSONEncoder().encode(step.params), encoding: .utf8) ?? "[]"
    return try store.appendHistoryStep(
      imageID: imageID, processID: step.processID, paramsJSON: json,
      output: HistoryStep.Output(path: path(of: step.file), bytes: Int64(bytes)), contentHash: nil)
  }

  /// Removes the outputs nothing refers to any more; the step is recorded whatever happens
  /// here, so a failure is logged, never reported as a failed Apply.
  private func cleanUp() {
    do {
      try session.history.save()
    } catch {
      Self.logger.error("history cleanup: \(String(describing: error), privacy: .public)")
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/studio")

  private func refresh() {
    steps = session.history.steps
    head = session.history.current
  }
}
