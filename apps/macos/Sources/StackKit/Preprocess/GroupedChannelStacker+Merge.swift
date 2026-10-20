internal import Foundation
internal import ImageKit

extension GroupedChannelStacker {
  /// Links every night's calibrated frames into `merged_<lane>`, registers them onto the anchor
  /// night's canvas (`registerMergedGroups`), grades per night and stacks.
  func mergeAndStack(
    _ merge: Merge, anchor: Int, filter: String, work: URL, out: URL, into outcome: inout ChannelOutcome
  ) async throws {
    let folder = work.appendingPathComponent("merged_" + ChannelTag.sanitize(filter))
    try? FileManager.default.removeItem(at: folder)
    defer { try? FileManager.default.removeItem(at: folder) }
    var light = ChannelStacker.Light(folder: folder, masters: CalibrationMasters(), ingest: .link)
    do {
      try MasterBuilder.link(merge.calibrated, into: folder)
      light.seq = try await register(folder, nights: merge.nights.count, filter: filter, into: &outcome)
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
    do {
      try await stacker.run(
        SirilScripts.applyRegistration(seq: light.seq, reference: review.referenceIndex, framing: "current"),
        in: folder)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      outcome.error = ChannelStacker.describe(error)
      return
    }
    var weighted = stacker
    weighted.settings.stack.weight = stackWeight(outcome.photometry, filter: filter, into: &outcome)
    try await weighted.gradeAndStack(
      light, frames: merge.frames, spans: merge.spans, preReject: review.preReject, into: &outcome, out: out)
    outcome.frameHomographies = review.frameHomographies
    outcome.nights = Self.contributions(outcome.nights, spans: merge.spans, grades: outcome.grades)
    for night in outcome.nights where night.stacked == 0 && night.frames > 0 {
      stacker.warn(
        "\(filter): night \(night.session.isEmpty ? "(undated)" : night.session) contributed no frames "
          + "to the stack (\(night.rejected) rejected)", into: &outcome)
    }
  }

  /// Flattens then registers (two-pass, homography); on a failed flatten the folder is put back
  /// to its links before the plain registration. Returns the registered sequence's base.
  ///
  /// The legacy engine re-linked in the uncleaned folder, so Siril's `link` took the flatten's
  /// leftover `light_*` links too and every frame was stacked twice (PO decision 2026-10-20: fixed).
  func register(_ folder: URL, nights: Int, filter: String, into outcome: inout ChannelOutcome) async throws
    -> String
  {
    if settings.flattenBackground && nights > 1 {
      do {
        try await stacker.run(
          SirilScripts.flattenRegister2Pass(seq: "light", transformation: "homography", degree: 1), in: folder)
        return "flat_light"
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        stacker.warn("\(filter): per-frame background flatten failed — registering unflattened", into: &outcome)
        try Self.keepLinks(in: folder)
      }
    }
    try await stacker.run(SirilScripts.register2Pass(seq: "light", transformation: "homography"), in: folder)
    return "light"
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
  func stackWeight(_ records: [PhotomGroupRecord], filter: String, into outcome: inout ChannelOutcome) -> String? {
    let preset = settings.stack.weight
    guard preset != "noise" else { return preset }
    let applied = records.filter { $0.applied && $0.scale > 0 }
    guard let worst = applied.max(by: { abs(log2($0.scale)) < abs(log2($1.scale)) }),
      abs(log2(worst.scale)) > 2
    else { return preset }
    stacker.warn(
      "\(filter): stack weighting switched to noise: group \"\(worst.label)\" normalized at ×"
        + "\(String(format: "%.3g", worst.scale)) — sharpness weighting cannot down-weight its amplified noise",
      into: &outcome)
    return "noise"
  }
}
