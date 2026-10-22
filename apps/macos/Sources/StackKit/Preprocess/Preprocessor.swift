package import Foundation

/// Runs one night's preprocessing as ordered steps: calibration masters → one step per channel
/// (calibrate, register, grade, stack) → align → combine → linear bundle.
///
/// Events stream in order; cancelling the consuming task stops the run between Siril commands,
/// keeping the masters already finished and writing no bundle. One run per output folder.
package actor Preprocessor {
  /// What the run calls out to; tests substitute Siril and the pixel decisions.
  package struct Tools: Sendable {
    package var runner: SirilRunner
    package var trailProbe: ChannelStacker.TrailProbe
    package var edgeMeasure: EdgeCropper.Measure
    /// Writes a stage's quick-look PNG from its FITS.
    package var preview: @Sendable (_ fits: URL, _ png: URL) throws -> Void

    /// The real tools over `runner`.
    package init(
      runner: SirilRunner,
      trailProbe: @escaping ChannelStacker.TrailProbe = ChannelStacker.pixelTrail,
      edgeMeasure: @escaping EdgeCropper.Measure = EdgeCropper.pixels,
      preview: @escaping @Sendable (URL, URL) throws -> Void = {
        try PreviewRenderer.render($0, to: $1)
      }
    ) {
      self.runner = runner
      self.trailProbe = trailProbe
      self.edgeMeasure = edgeMeasure
      self.preview = preview
    }
  }

  let tools: Tools

  /// A preprocessor using `tools`.
  package init(tools: Tools) {
    self.tools = tools
  }

  /// Starts `request`; the stream ends with `.finished`, or throws the run's error (a
  /// `CancellationError` when the consumer cancelled).
  package nonisolated func run(_ request: PreprocessRequest) -> AsyncThrowingStream<
    PreprocessEvent, any Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let result = try await self.perform(request) { continuation.yield($0) }
          continuation.yield(.finished(result))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The run itself; `sink` receives every event but the last.
  package func perform(
    _ request: PreprocessRequest, sink: @escaping @Sendable (PreprocessEvent) -> Void
  ) async throws -> PreprocessResult {
    try TargetLock.acquire(request.output)
    defer { TargetLock.release(request.output) }
    let plan = try Self.plan(request.inventory)
    let lanes = ChannelAligner.ordered(plan.channels.keys)
    let emitter = RunEmitter(steps: lanes.count + 4, sink: sink)
    var journal = PreprocessJournal { emitter.line($0) }
    for folder in [request.output, request.work] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    var result = PreprocessResult(runID: request.runID)
    let pool = try await buildMasters(request, emitter: emitter, into: &result)
    let parity = ParityCache(runner: tools.runner, coordinates: request.settings.solveCoordinates)
    for lane in lanes {
      try Task.checkCancellation()
      let outcome = try await stackChannel(
        lane, plan: plan, request: request, pool: pool, parity: parity, emitter: emitter)
      if let error = outcome.error {
        journal.warn("channel \(outcome.filter) failed — continuing without it: \(error)")
      }
      result.warnings += outcome.warnings
      result.channels.append(outcome)
    }
    // The verdicts outlive the work folder: the Tri stage reads them back (card 0069). A record
    // that cannot be written is a warning, never the end of a run whose lanes are all stacked.
    do {
      try GradesRecord(result: result).write(to: request.output)
    } catch {
      journal.warn(
        "grades.json not written — the Tri stage will show nothing for this run: \(error)")
    }
    try await assemble(request, emitter: emitter, journal: &journal, into: &result)
    result.warnings += journal.warnings
    return result
  }

  /// Which nights feed which channel (lane).
  ///
  /// A capture measured both broadband and dual-band stacks two lanes. A mono + colour mix, or
  /// lights of several objects (card 0095: one object per run, scoped by `RunScope`), is refused
  /// before anything runs.
  package static func plan(_ inventory: Inventory) throws -> NightPlan {
    guard inventory.colorModel != .mixed else { throw PreprocessError.mixedColorModel }
    let lights = inventory.sets.filter { $0.key.type == .light }
    guard !lights.isEmpty else { throw PreprocessError.noLights }
    // An unnamed OBJECT is an object of its own: never merged into a named one in silence.
    let objects = Set(lights.map(\.key.object))
    guard objects.count <= 1 else { throw PreprocessError.mixedObjects(objects.sorted()) }
    let split = FilterSetLanes.splits(inventory)
    return NightPlan(inventory.sets.filter { $0.key.type == .light }) {
      FilterSetLanes.lane(for: $0, in: inventory, split: split)
    }
  }
}
