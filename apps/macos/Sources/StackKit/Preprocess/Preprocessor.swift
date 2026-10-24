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

  /// How a run ended: with its result, or paused after a lane (card 0097).
  package enum Ending: Equatable, Sendable {
    case finished(PreprocessResult)
    case paused(PreprocessCheckpoint)
  }

  /// Starts `request`.
  ///
  /// The stream ends with `.finished`, or `.paused` once its `pause` gate was requested with lanes
  /// left, or throws the run's error (a `CancellationError` when the consumer cancelled). A
  /// `resuming` request reuses every lane whose `LaneRecord` still matches.
  package nonisolated func run(_ request: PreprocessRequest) -> AsyncThrowingStream<
    PreprocessEvent, any Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          switch try await self.execute(request, sink: { continuation.yield($0) }) {
          case .finished(let result): continuation.yield(.finished(result))
          case .paused(let checkpoint): continuation.yield(.paused(checkpoint))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The run to its result.
  ///
  /// `sink` receives every event but the last. A run that paused (its request carried a gate)
  /// ends without one: `CancellationError`.
  package func perform(
    _ request: PreprocessRequest, sink: @escaping @Sendable (PreprocessEvent) -> Void
  ) async throws -> PreprocessResult {
    switch try await execute(request, sink: sink) {
    case .finished(let result): return result
    case .paused: throw CancellationError()
    }
  }

  /// The run, to its result or its pause.
  ///
  /// `sink` receives every event but the last. A lane is the unit: a pause asked during a lane
  /// ends the run once that lane's master and record are written, unless it was the last.
  package func execute(
    _ request: PreprocessRequest, sink: @escaping @Sendable (PreprocessEvent) -> Void
  ) async throws -> Ending {
    try TargetLock.acquire(request.output)
    defer { TargetLock.release(request.output) }
    let plan = try Self.plan(request.inventory)
    let lanes = ChannelAligner.ordered(plan.channels.keys)
    let emitter = RunEmitter(steps: lanes.count + 4, sink: sink)
    var journal = PreprocessJournal { emitter.line($0) }
    for folder in [request.output, request.work] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    // Tens of GB of Siril files: a killed app's are swept at the next launch (LeftoverSweep).
    // Best effort: an unmarked folder is only never swept, never a run that cannot start.
    try? ScratchOwner.mark(request.work)
    var result = PreprocessResult(runID: request.runID)
    // Built when a lane first needs them: a resume whose lanes are all reused calls no Siril.
    var pool: [CalibrationMaster]?
    let run = LaneRun(
      plan: plan, request: request,
      parity: ParityCache(runner: tools.runner, coordinates: request.settings.solveCoordinates),
      emitter: emitter)
    for (index, lane) in lanes.enumerated() {
      try Task.checkCancellation()
      let outcome = try await laneOutcome(
        lane, of: run, pool: &pool, journal: &journal, result: &result)
      if let error = outcome.error {
        journal.warn("channel \(outcome.filter) failed — continuing without it: \(error)")
      }
      result.warnings += outcome.warnings
      result.channels.append(outcome)
      let left = Array(lanes[(index + 1)...])
      if request.pause?.isRequested == true, !left.isEmpty {
        journal.line("paused after \(lane) — Continue stacks \(left.joined(separator: ", "))")
        return .paused(
          PreprocessCheckpoint(
            runID: request.runID, lanesDone: Array(lanes[...index]), lanesLeft: left))
      }
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
    return .finished(result)
  }

  /// Which nights feed which channel (lane).
  ///
  /// A capture measured both broadband and dual-band stacks two lanes. A mono + colour mix, or
  /// lights of several objects (card 0095: one object per run, scoped by `RunScope`), is refused
  /// before anything runs.
  package static func plan(_ inventory: Inventory) throws -> NightPlan {
    let lights = inventory.sets.filter { $0.key.type == .light }
    guard !lights.isEmpty else { throw PreprocessError.noLights }
    // An unnamed OBJECT is an object of its own: never merged into a named one in silence. The
    // objects are checked before the colour model: two rigs on two objects are two runs, not a
    // colour kind to exclude.
    let objects = Set(lights.map(\.key.object))
    guard objects.count <= 1 else { throw PreprocessError.mixedObjects(objects.sorted()) }
    guard inventory.colorModel != .mixed else { throw PreprocessError.mixedColorModel }
    let split = FilterSetLanes.splits(inventory)
    return NightPlan(lights) {
      FilterSetLanes.lane(for: $0, in: inventory, split: split)
    }
  }
}
