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
  /// The first step that read a branch head which moved since (card 0118), or `nil`.
  package private(set) var staleFrom: Int?
  /// The applied steps of each opened branch, by layer id (card 0119).
  package private(set) var branchSteps: [String: [History.Step]] = [:]
  /// The head of each branch with a step, read once per move (a branch history hands out copies).
  @ObservationIgnored private(set) var branchHeads: [String: AstroImage] = [:]
  /// The working image: the history's head.
  package private(set) var head: AstroImage
  /// The stack's header (its base layer's): where suggestions read pointing and optics.
  @ObservationIgnored package let header: FITSHeader?

  @ObservationIgnored let store: ProjectStore
  /// The project image (role `studio`) the history is mirrored on.
  @ObservationIgnored package let imageID: Int64
  /// The stack whose layers' rows the branches are mirrored on.
  @ObservationIgnored let stackID: Int64
  @ObservationIgnored let packageRoot: URL

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
    let directory = stackFolder.appendingPathComponent("history")
    let branches = try BranchSet(
      folder: BranchSet.folder(besides: directory), bundle: bundle, header: header
    ) { registry.type(id: $0)?.schema }
    // Every step keeps the stack's descriptive cards (WCS, OBJECT…); the session starts it from
    // the base layer's branch head (card 0118).
    let history = try History.reopen(
      directory: directory, original: base, header: header,
      movesPixels: registry.movesPixels
    ) { registry.type(id: $0)?.schema ?? Self.batchSchemas[$0] }
    session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device, branches: branches)
    self.store = store
    self.header = header
    self.stackID = stackID
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
    refresh()
    refreshBranches()
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

  /// Back `steps` steps, mirrored once (a pipeline run undone in one move, card 0117); a
  /// failure puts back the steps already undone.
  package func undo(steps: Int = 1) throws {
    defer { mirror() }
    let history = session.history
    try Self.move(steps, by: history.undo, back: history.redo)
  }

  /// Forward `steps` undone steps, mirrored once; a failure takes back those already redone.
  package func redo(steps: Int = 1) throws {
    defer { mirror() }
    let history = session.history
    try Self.move(steps, by: history.redo, back: history.undo)
  }

  /// Makes `step` `count` times, all or none: a move that fails half-way never leaves the head
  /// between where it started and where it was going.
  private static func move(
    _ count: Int, by step: () throws -> Void, back: () throws -> Void
  ) throws {
    var done = 0
    do {
      while done < count {
        try step()
        done += 1
      }
    } catch {
      for _ in 0..<done { try? back() }
      throw error
    }
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
    mirror(session.history, on: imageID)
  }

  /// Brings the rows of project image `imageID` in line with `history` (the main one, or a
  /// branch's on its layer's row).
  func mirror(_ history: History, on imageID: Int64) {
    do {
      let kept = history.steps + history.undone.reversed()
      var rows = try store.history(imageID: imageID)
      let wanted = Set(kept.map { path(of: $0.file, in: history) })
      for row in rows where !wanted.contains(row.outputPath ?? "") {
        try store.deleteHistoryStep(id: row.id)
      }
      rows = rows.filter { wanted.contains($0.outputPath ?? "") }
      for step in kept
      where !rows.contains(where: { $0.outputPath == path(of: step.file, in: history) }) {
        rows.append(try appendRow(step, of: history, on: imageID))
      }
      let head = history.steps.last.flatMap { last in
        rows.first { $0.outputPath == path(of: last.file, in: history) }?.id
      }
      try store.setHead(imageID: imageID, stepID: head)
    } catch {
      // The rows only mirror the history (its files are the truth): a failed write is retried
      // by the next move.
      Self.logger.error("history mirror: \(String(describing: error), privacy: .public)")
    }
  }

  private func path(of file: String, in history: History) -> String {
    let url = history.directory.appendingPathComponent(file)
    return String(url.path.dropFirst(packageRoot.path.count + 1))
  }

  private func appendRow(_ step: History.Step, of history: History, on imageID: Int64) throws
    -> HistoryStep
  {
    // The step's image and the layers it wrote or rewrote: what the disk budget counts.
    let files = [step.file] + step.outputs.values + step.replaced.values
    let bytes = files.reduce(0) { total, file in
      let url = history.directory.appendingPathComponent(file)
      let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
      return total + (size ?? 0)
    }
    let json = String(bytes: try JSONEncoder().encode(step.params), encoding: .utf8) ?? "[]"
    return try store.appendHistoryStep(
      imageID: imageID, processID: step.processID, paramsJSON: json,
      output: HistoryStep.Output(path: path(of: step.file, in: history), bytes: Int64(bytes)),
      contentHash: nil)
  }

  /// Removes the outputs nothing refers to any more; the step is recorded whatever happens
  /// here, so a failure is logged, never reported as a failed Apply.
  func cleanUp(_ history: History? = nil) {
    do {
      try (history ?? session.history).save()
    } catch {
      Self.logger.error("history cleanup: \(String(describing: error), privacy: .public)")
    }
  }

  static let logger = Logger(subsystem: "fr.astrostack", category: "App/studio")

  func refresh() {
    steps = session.history.steps
    head = session.history.current
    staleFrom = session.staleFrom
  }

  /// Reads the steps and head of branch `layerID` again (every opened branch when `nil`): after
  /// a branch move only, and only that branch (a head is a full copy).
  func refreshBranches(_ layerID: String? = nil) {
    for branch in session.branches.all where layerID == nil || branch.layerID == layerID {
      branchSteps[branch.layerID] = branch.history.steps
      branchHeads[branch.layerID] = branch.head
    }
  }
}
