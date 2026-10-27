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

  /// One channel's step (the plan's nights of `lane`), its master previewed when there is one.
  func stackChannel(
    _ lane: String, plan: NightPlan, request: PreprocessRequest, pool: [CalibrationMaster],
    parity: ParityCache, emitter: RunEmitter, note: String? = nil
  ) async throws -> ChannelOutcome {
    let groups = plan.channels[lane] ?? []
    let object = groups.first?.key.object ?? ""
    emitter.begin(
      "grading + stacking \(object) \(lane)" + (groups.count > 1 ? " (\(groups.count) groups)" : "")
    )
    // Why a resumed run stacks this lane again (card 0097), under the lane's own step.
    if let note { emitter.line(note) }
    // The lane's own knobs (card 0121): the run's settings unless a split run overrides its kind.
    let settings = request.settings(forLane: lane, in: plan)
    // The stacker journals its own Siril lines and warnings.
    var stacker = ChannelStacker(
      runner: tools.runner, settings: settings, trailProbe: tools.trailProbe
    ) { emitter.line($0) }
    if settings.frameReview {
      stacker.frameReview = frameReviewHook(work: request.work, emitter: emitter)
    }
    if settings.referenceBreakpoint {
      stacker.referencePin = referencePinHook(emitter: emitter)
    }
    let outcome: ChannelOutcome
    if plan.anchored {
      // Every channel of an anchored run lands on the anchor night's canvas, a one-night one too.
      outcome = try await GroupedChannelStacker(
        stacker: stacker, parity: parity, anchorNight: plan.anchorNight
      ).stack(
        groups, filter: lane, inventory: request.inventory, masters: pool, work: request.work,
        out: request.output)
    } else {
      outcome = try await stacker.stack(
        groups[0], filter: lane, inventory: request.inventory, masters: pool, work: request.work,
        out: request.output)
    }
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
    // Read before the crops rename the inputs: only an aligned line-clip master may be split.
    let laneRegistered = FilterSetLanes.lineLanes(in: channels.keys).allSatisfy {
      channels[$0]?.hasPrefix("aligned_") == true
    }
    channels = crop(channels, request: request, journal: &journal, into: &result)
    var notes: [String] = []
    let continuum: [String: ContinuumK.Fit]
    (channels, continuum) = Self.emissionFits(
      channels, out: request.output, registered: laneRegistered, notes: &notes)
    for note in notes { journal.line(note) }
    result.notes += notes
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
          source: LayerPrecedence.stage(of: base) ?? String(base.prefix { $0 != "_" }),
          continuumK: continuum[filter]?.k, continuumReference: continuum[filter]?.plane)
      },
      to: request.output)
  }

  /// The common-coverage crop (multi-night channels carry coverage), then the edge trim.
  private func crop(
    _ channels: [String: String], request: PreprocessRequest, journal: inout PreprocessJournal,
    into result: inout PreprocessResult
  ) -> [String: String] {
    var channels = channels
    if request.settings.coverageCrop {
      let grids = result.channels.reduce(into: [String: CoverageGrid]()) { grids, channel in
        if let grid = channel.coverage, channel.error == nil { grids[channel.filter] = grid }
      }
      (channels, result.coverageCrop) = CoverageCrop.apply(
        channels, grids: grids, minimumFraction: request.settings.coverageMinimumFraction,
        out: request.output, journal: &journal)
    }
    if request.settings.edgeCrop {
      (channels, result.crop) = EdgeCropper(measure: tools.edgeMeasure).apply(
        channels, out: request.output, journal: &journal)
    }
    return channels
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
