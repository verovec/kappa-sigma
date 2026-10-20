internal import Foundation
internal import ImageKit

extension GroupedChannelStacker {
  /// Links every night's calibrated frames into `merged_<lane>`, registers them onto the anchor
  /// night's canvas (`registerMergedGroups`), grades per night and stacks.
  func mergeAndStack(
    _ merge: Merge, anchor: Int, filter: String, work: URL, out: URL,
    into outcome: inout ChannelOutcome
  ) async throws {
    let folder = work.appendingPathComponent("merged_" + ChannelTag.sanitize(filter))
    try? FileManager.default.removeItem(at: folder)
    defer { try? FileManager.default.removeItem(at: folder) }
    var light = ChannelStacker.Light(folder: folder, masters: CalibrationMasters(), ingest: .link)
    do {
      try MasterBuilder.link(merge.calibrated, into: folder)
      light.seq = try await register(
        folder, nights: merge.nights.count, filter: filter, into: &outcome)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      outcome.error = ChannelStacker.describe(error)
      return
    }
    let size = DimensionGuard.dimensions(merge.calibrated[0])
    let review = RegistrationReview(
      try ChannelStacker.sequence(of: light), spans: merge.spans, anchor: anchor,
      width: size?.width ?? 0, height: size?.height ?? 0)
    for warning in review.warnings { stacker.warn("\(filter): \(warning)", into: &outcome) }
    outcome.nights = Self.nights(merge, review: review)
    // The homographies are known but no registered pixel is written yet: each night's pedestal
    // can still be refitted in place before `seqapplyreg` reads the frames.
    if settings.seamOffsetRefit && merge.nights.count > 1 {
      let base = light.seq
      outcome.seamOffsets = try SeamOffsetRefit.refit(
        merge.nights, spans: merge.spans, anchor: anchor, review: review,
        frameSize: (size?.width ?? 0, size?.height ?? 0)
      ) { folder.appendingPathComponent(base + String(format: "_%05d.fits", $0 + 1)) }
    }
    guard try await applyRegistration(light, review: review, into: &outcome) else { return }
    var weighted = stacker
    weighted.settings.stack.weight = stackWeight(outcome.photometry, filter: filter, into: &outcome)
    try await weighted.gradeAndStack(
      light, frames: merge.frames, spans: merge.spans, preReject: review.preReject,
      saturationCeilings: saturationCeilings(merge, records: outcome.photometry), into: &outcome,
      out: out)
    summarise(merge, review: review, size: size, filter: filter, into: &outcome)
  }

  /// Writes the registered frames (`seqapplyreg`); false, the error recorded, when Siril fails.
  func applyRegistration(
    _ light: ChannelStacker.Light, review: RegistrationReview, into outcome: inout ChannelOutcome
  ) async throws -> Bool {
    do {
      try await stacker.run(
        SirilScripts.applyRegistration(
          seq: light.seq, reference: review.referenceIndex, framing: "current"),
        in: light.folder)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      outcome.error = ChannelStacker.describe(error)
      return false
    }
    return true
  }

  /// After the stack: the coverage grid, the seam noise equalisation and the per-night
  /// contributions, a night that contributed nothing warned about.
  func summarise(
    _ merge: Merge, review: RegistrationReview, size: DimensionGuard.Size?, filter: String,
    into outcome: inout ChannelOutcome
  ) {
    outcome.frameHomographies = review.frameHomographies
    if let size {
      let grades = outcome.grades
      outcome.coverage = CoverageGrid(
        homographies: review.frameHomographies,
        rejected: { $0 >= grades.count || grades[$0].rejected || grades[$0].fwhm <= 0 },
        frameWidth: size.width, frameHeight: size.height)
    }
    // The full-depth core stays byte for byte; the shallow margins get the excess noise removed.
    if settings.seamNoiseEqualisation, let path = outcome.masterPath, let grid = outcome.coverage {
      let record = SeamNoiseEqualiser.equalise(
        URL(fileURLWithPath: path), grid: grid, budget: stacker.memoryBudget)
      outcome.seamNoise = record
      if record.overBudget {
        stacker.warn("\(filter): seam noise equalization \(record.reason)", into: &outcome)
      }
    }
    outcome.nights = Self.contributions(outcome.nights, spans: merge.spans, grades: outcome.grades)
    for night in outcome.nights where night.stacked == 0 && night.frames > 0 {
      stacker.warn(
        "\(filter): night \(night.session.isEmpty ? "(undated)" : night.session) "
          + "contributed no frames to the stack (\(night.rejected) rejected)", into: &outcome)
    }
  }

  /// Flattens then registers (two-pass, homography).
  ///
  /// On a failed flatten the folder is put back to its links before the plain registration. Returns
  /// the registered sequence's base.
  ///
  /// The legacy engine re-linked in the uncleaned folder, so Siril's `link` took the flatten's
  /// leftover `light_*` links too and every frame was stacked twice (PO decision 2026-10-20: fixed).
  func register(_ folder: URL, nights: Int, filter: String, into outcome: inout ChannelOutcome)
    async throws
    -> String
  {
    if settings.flattenBackground && nights > 1 {
      do {
        try await stacker.run(
          SirilScripts.flattenRegister2Pass(seq: "light", transformation: "homography", degree: 1),
          in: folder)
        return "flat_light"
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        stacker.warn(
          "\(filter): per-frame background flatten failed — registering unflattened", into: &outcome
        )
        try Self.keepLinks(in: folder)
      }
    }
    try await stacker.run(
      SirilScripts.register2Pass(seq: "light", transformation: "homography"), in: folder)
    return "light"
  }

  /// Each merged frame's post-normalisation saturation ceiling (`satCeilings`): its night's
  /// `scale · 0.97 + offset`, 0.97 for an untransformed night; empty when the repair is off or
  /// the channel has a single night (no unsaturated night to draw on).
  func saturationCeilings(_ merge: Merge, records: [PhotomGroupRecord]) -> [Float] {
    guard settings.coreSaturationRepair, merge.spans.count >= 2 else { return [] }
    var ceilings = [Float](repeating: 0, count: merge.calibrated.count)
    for (night, span) in merge.spans.enumerated() {
      let ceiling =
        night < records.count && records[night].saturationCeiling > 0
        ? Float(records[night].saturationCeiling) : FrameCurve.saturationLevel
      for index in span where index < ceilings.count { ceilings[index] = ceiling }
    }
    return ceilings
  }

  /// Removes everything but the `00001_…` links from a merge folder.
  static func keepLinks(in folder: URL) throws {
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
    where !(name.first?.isNumber == true && name.dropFirst(5).first == "_") {
      try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
  }

  /// The weighting: the preset's, or `noise` when a night was rewritten beyond ×4 either way
  /// (`photomStackWeight`): sharpness weighting cannot down-weight amplified noise.
  func stackWeight(
    _ records: [PhotomGroupRecord], filter: String, into outcome: inout ChannelOutcome
  ) -> String? {
    let preset = settings.stack.weight
    guard preset != "noise" else { return preset }
    let applied = records.filter { $0.applied && $0.scale > 0 }
    guard let worst = applied.max(by: { abs(log2($0.scale)) < abs(log2($1.scale)) }),
      abs(log2(worst.scale)) > 2
    else { return preset }
    stacker.warn(
      "\(filter): stack weighting switched to noise: group \"\(worst.label)\" normalized at ×"
        + "\(String(format: "%.3g", worst.scale)) — sharpness weighting cannot down-weight "
        + "its amplified noise",
      into: &outcome)
    return "noise"
  }
}
