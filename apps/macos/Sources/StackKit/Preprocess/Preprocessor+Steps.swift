internal import Foundation

extension Preprocessor {
  /// Step 1: the run's calibration masters; returns the pool the lights are matched against.
  func buildMasters(
    _ request: PreprocessRequest, emitter: RunEmitter, into result: inout PreprocessResult
  )
    async throws -> [CalibrationMaster]
  {
    emitter.begin("building master calibration frames")
    let built = try await MasterBuilder(runner: reporting(emitter)).build(
      request.inventory, into: request.work.appendingPathComponent("masters"), work: request.work,
      library: request.library)
    result.masters = built.masters
    result.warnings += built.warnings
    return built.pool
  }

  /// One channel's step, its master previewed when there is one.
  func stackChannel(
    _ set: FrameSet, request: PreprocessRequest, pool: [CalibrationMaster], emitter: RunEmitter
  ) async throws -> ChannelOutcome {
    emitter.begin("grading + stacking \(set.key.object) \(set.key.filter)")
    // The stacker journals its own Siril lines and warnings.
    let stacker = ChannelStacker(
      runner: tools.runner, settings: request.settings, trailProbe: tools.trailProbe
    ) { emitter.line($0) }
    let outcome = try await stacker.stack(
      set, filter: set.key.filter, inventory: request.inventory, masters: pool, work: request.work,
      out: request.output)
    if let master = outcome.masterPath {
      preview(URL(fileURLWithPath: master), emitter: emitter)
    }
    return outcome
  }

  /// Align, crop, combine, bundle.
  func assemble(
    _ request: PreprocessRequest, emitter: RunEmitter, journal: inout PreprocessJournal,
    into result: inout PreprocessResult
  ) async throws {
    let masters = result.channels.reduce(into: [String: String]()) { masters, channel in
      if let path = channel.masterPath { masters[channel.filter] = path }
    }
    guard !masters.isEmpty else {
      throw PreprocessError.noChannels(result.channels.compactMap { $0.error.map { "\($0)" } })
    }
    try Task.checkCancellation()
    emitter.begin("aligning channels")
    var channels = try await ChannelAligner(
      runner: reporting(emitter), coordinates: request.settings.solveCoordinates
    ).align(
      masters, folder: request.work.appendingPathComponent("04_aligned"), out: request.output,
      journal: &journal)
    if request.settings.edgeCrop {
      (channels, result.crop) = EdgeCropper(measure: tools.edgeMeasure).apply(
        channels, out: request.output, journal: &journal)
    }
    try Task.checkCancellation()
    emitter.begin("combining channels (Siril)")
    let combiner = ChannelCombiner(runner: reporting(emitter), settings: request.settings)
    if let combined = try await combiner.combine(channels, out: request.output) {
      result.combinedPath = combined.path
      preview(combined, emitter: emitter)
    }
    try Task.checkCancellation()
    emitter.begin("writing the linear bundle")
    result.bundle = try BundleWriter().write(
      runID: request.runID, colorModel: request.inventory.colorModel,
      layers: ChannelAligner.ordered(channels.keys).map { filter in
        let base = channels[filter] ?? ""
        return BundleWriter.Input(
          filter: filter, file: request.output.appendingPathComponent(base + ".fits"),
          source: LayerPrecedence.stage(of: base) ?? String(base.prefix { $0 != "_" }))
      },
      to: request.output)
  }

  /// `tools.runner` with every Siril line on the journal.
  private func reporting(_ emitter: RunEmitter) -> SirilRunner {
    let runner = tools.runner
    return SirilRunner { script, folder, onLine in
      try await runner.run(script, folder) { line in
        emitter.line(line.text)
        onLine(line)
      }
    }
  }

  /// `<stage>_preview.png` beside the FITS; a preview that fails is skipped (display only).
  private func preview(_ fits: URL, emitter: RunEmitter) {
    let stage = fits.deletingPathExtension().lastPathComponent
    let png = fits.deletingLastPathComponent().appendingPathComponent(stage + "_preview.png")
    guard (try? tools.preview(fits, png)) != nil else { return }
    emitter.preview(stage: stage, png: png)
  }
}
