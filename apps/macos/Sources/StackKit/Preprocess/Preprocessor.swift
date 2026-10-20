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
    let lights = try Self.lightSets(request.inventory)
    let emitter = RunEmitter(steps: lights.count + 4, sink: sink)
    var journal = PreprocessJournal { emitter.line($0) }
    for folder in [request.output, request.work] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    var result = PreprocessResult(runID: request.runID)
    let pool = try await buildMasters(request, emitter: emitter, into: &result)
    for set in lights {
      try Task.checkCancellation()
      let outcome = try await stackChannel(set, request: request, pool: pool, emitter: emitter)
      if let error = outcome.error {
        journal.warn("channel \(outcome.filter) failed — continuing without it: \(error)")
      }
      result.warnings += outcome.warnings
      result.channels.append(outcome)
    }
    try await assemble(request, emitter: emitter, journal: &journal, into: &result)
    result.warnings += journal.warnings
    return result
  }

  /// The light sets in canonical filter order; a filter captured over several nights (or a
  /// mono + colour mix) is refused before anything runs.
  package static func lightSets(_ inventory: Inventory) throws -> [FrameSet] {
    guard inventory.colorModel != .mixed else { throw PreprocessError.mixedColorModel }
    let lights = inventory.sets.filter { $0.key.type == .light }
    let filters = lights.map(\.key.filter)
    let repeated = Set(filters.filter { filter in filters.count { $0 == filter } > 1 })
    guard repeated.isEmpty else {
      throw PreprocessError.multiNight(ChannelAligner.ordered(repeated))
    }
    return lights.sorted { Filter.less($0.key.filter, $1.key.filter) }
  }
}
