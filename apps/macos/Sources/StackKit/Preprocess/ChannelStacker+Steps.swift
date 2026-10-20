package import Foundation
internal import ImageKit

extension ChannelStacker {
  /// Calibrates and registers the sequence (`calibrateAndRegister`); the two-pass form notes the
  /// reference Siril elected, then applies the registration on the reference's own field.
  func calibrateRegister(_ light: Light, into outcome: inout ChannelOutcome) async throws {
    let twoPass = settings.register2Pass
    try await run(
      SirilScripts.calibrateRegister(
        seq: light.seq, masters: light.masters, ingest: light.ingest, twoPass: twoPass),
      in: light.folder)
    guard twoPass else { return }
    if let note = Self.referenceNote(light, filter: outcome.filter) {
      outcome.selection.notes.append(note)
    }
    try await run(
      SirilScripts.applyRegistration(seq: light.calibrated, reference: 0, framing: "current"),
      in: light.folder)
  }

  /// Which frame the two-pass metric pass elected (`noteRegistrationReference`); nil when the
  /// `.seq` does not say.
  static func referenceNote(_ light: Light, filter: String) -> String? {
    guard let sequence = try? sequence(of: light), sequence.reference >= 0,
      sequence.reference < sequence.metrics.count
    else { return nil }
    let metric = sequence.metrics[sequence.reference]
    return "\(filter): two-pass registration elected frame \(sequence.reference + 1)/"
      + "\(sequence.metrics.count) as reference (\(metric.starCount) stars, FWHM "
      + "\(String(format: "%.2f", metric.fwhm)) px) instead of defaulting to frame 1"
  }

  /// The calibrated sequence's `.seq`.
  static func sequence(of light: Light) throws -> SirilSequence {
    let url = light.folder.appendingPathComponent(light.calibrated + "_.seq")
    guard let text = String(bytes: try Data(contentsOf: url), encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return SirilSequence(parsing: text)
  }

  /// Grades the registered frames and stacks the survivors (`finishStackedChannel`).
  func gradeAndStack(
    _ light: Light, frames: [CaptureFrame], spans: [Range<Int>] = [],
    preReject: [Int: String] = [:],
    saturationCeilings: [Float] = [], into outcome: inout ChannelOutcome, out: URL
  ) async throws {
    let sequence: SirilSequence
    do {
      sequence = try Self.sequence(of: light)
    } catch {
      outcome.error = "grading: \(Self.describe(error))"
      return
    }
    let size = settings.trailDownsample
    // Each probe reads a whole frame: a cancelled run stops between them.
    let graded = try ChannelGrading.grade(
      sequence, frames: frames, settings: settings, preReject: preReject, spans: spans
    ) { index in
      try Task.checkCancellation()
      return trailProbe(light.frame(light.calibrated, index + 1), size)
    }
    outcome.grades = graded.grades
    outcome.stackedFrames = graded.registeredCount - graded.rejectedRegistered.count
    guard graded.registeredCount > 0 else {
      outcome.error = "no frames could be registered"
      return
    }
    for warning in ChannelOutcome.gradingWarnings(
      filter: outcome.filter, grades: graded.grades, registered: graded.registeredCount,
      survivors: outcome.stackedFrames)
    {
      warn(warning, into: &outcome)
    }
    // The merge-order ceilings follow the registered numbering.
    let ceilings = zip(graded.grades, saturationCeilings).filter { $0.0.fwhm > 0 }.map(\.1)
    try await maskRegistered(
      (0..<graded.registeredCount).map { light.frame(light.registered, $0 + 1) },
      saturationCeilings: ceilings, into: &outcome)
    let master = out.appendingPathComponent("master_" + ChannelTag.of(outcome.filter))
    try await stackOrCopy(light, graded: graded, master: master, into: &outcome)
    finish(master, into: &outcome)
  }

  /// The registered frames' cross-frame pass (`applyTrailMask`).
  ///
  /// Saturated cores repaired first, then the trail mask when k > 0, one note for both. Under five
  /// frames nothing runs; a failure is noted and the frames are stacked as they are.
  package func maskRegistered(
    _ files: [URL], saturationCeilings: [Float], into outcome: inout ChannelOutcome
  ) async throws {
    guard files.count >= TrailMask.minimumFrames else { return }
    var summary = TrailMaskSummary(frames: files.count)
    var mode: String?
    do {
      let saturated =
        saturationCeilings.contains { $0 > 0 }
        ? try SaturationRepair.repair(files, ceilings: saturationCeilings).reduce(0, +) : 0
      if settings.trailMaskK > 0 {
        report("▶ transient trail mask (cross-frame) …")
        if let masked = try await ChannelTrailMask.mask(
          files, k: settings.trailMaskK, budget: memoryBudget)
        {
          (summary, mode) = (masked.summary, masked.mode)
        }
      }
      summary.saturatedPixels = saturated
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      outcome.selection.notes.append("trail mask skipped: \(Self.describe(error))")
      return
    }
    guard summary.maskedPixels > 0 || summary.saturatedPixels > 0 else { return }
    let size = DimensionGuard.dimensions(files[0].path)
    outcome.trailMask = summary
    outcome.selection.notes.append(
      ChannelTrailMask.note(
        summary, width: size?.width ?? 0, height: size?.height ?? 0, mode: mode))
  }

  /// One registered frame is the master; fewer than two survivors cannot stack; otherwise Siril
  /// stacks the selection (`stackSelectedOrCopy`).
  private func stackOrCopy(
    _ light: Light, graded: ChannelGrading.Outcome, master: URL, into outcome: inout ChannelOutcome
  ) async throws {
    let count = graded.registeredCount
    if count == 1 {
      try FileReplace.copy(
        light.frame(light.registered, 1), over: master.appendingPathExtension("fits"))
      warn(
        "\(outcome.filter): only 1 frame registered — using it as the channel master (no stacking)",
        into: &outcome)
      return
    }
    let survivors = count - graded.rejectedRegistered.count
    guard survivors >= 2 else {
      throw PreprocessError.belowStackMinimum(survivors: survivors, registered: count)
    }
    try await run(
      SirilScripts.stackSelected(
        registered: light.registered, count: count, rejected: graded.rejectedRegistered,
        out: master.path, options: settings.stack),
      in: light.folder)
  }

  /// A one-frame set: calibrated alone and promoted (`promoteLoneCalibrated`).
  func promoteLone(_ light: Light, into outcome: inout ChannelOutcome, out: URL) async throws {
    try await run(
      SirilScripts.calibrateSingle(seq: light.seq, masters: light.masters, ingest: light.ingest),
      in: light.folder)
    warn(
      "\(outcome.filter): only 1 frame captured — using it as the channel master "
        + "(no registration/stacking)", into: &outcome)
    let master = out.appendingPathComponent("master_" + ChannelTag.of(outcome.filter))
    try FileReplace.copy(
      light.frame(light.calibrated, 1), over: master.appendingPathExtension("fits"))
    outcome.stackedFrames = 1
    finish(master, into: &outcome)
  }

  /// The linear master's finishing (`finishLinearMaster`): a BAYERPAT inherited from older mono
  /// captures would make Siril read the master as a mosaic; stripping it is cosmetic (soft).
  private func finish(_ master: URL, into outcome: inout ChannelOutcome) {
    let file = master.appendingPathExtension("fits")
    outcome.masterPath = file.path
    do {
      try FITSFile.stripKeyword("BAYERPAT", at: file)
    } catch {
      outcome.selection.notes.append("BAYERPAT strip skipped: \(Self.describe(error))")
    }
  }
}
