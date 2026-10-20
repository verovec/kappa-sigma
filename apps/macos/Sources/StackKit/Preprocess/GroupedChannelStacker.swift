package import Foundation
internal import ImageKit

/// A channel captured over several nights (`processChannelGroups`): each night calibrated with
/// its own masters and parity-checked, the nights mapped onto the anchor night's photometric
/// scale, the frames merged, flattened and registered onto the anchor night's canvas, graded per
/// night and stacked.
package struct GroupedChannelStacker: Sendable {
  package var stacker: ChannelStacker
  package var parity: ParityCache

  /// A grouped stacker sharing `stacker`'s runner, settings and probes; `parity` is the run's.
  package init(stacker: ChannelStacker, parity: ParityCache) {
    self.stacker = stacker
    self.parity = parity
  }

  var settings: PreprocessSettings { stacker.settings }

  /// What the night loop produced, in merge order.
  struct Merge {
    var calibrated: [String] = []
    var spans: [Range<Int>] = []
    var frames: [CaptureFrame] = []
    var photometry: [PhotomGroup] = []
    var nights: [FrameSet] = []
  }

  /// Stacks `groups` (one per night, in plan order) as channel `filter`.
  package func stack(
    _ groups: [FrameSet], filter: String, anchorNight: String, inventory: Inventory,
    masters: [CalibrationMaster], work: URL, out: URL
  ) async throws -> ChannelOutcome {
    let representative = CalibrationMatcher.select(groups[0], in: inventory, masters: masters)
    var outcome = ChannelOutcome(groups[0], filter: filter, selection: representative)
    outcome.inputFrames = 0
    var merge = Merge()
    for (index, group) in groups.enumerated() {
      try await calibrate(
        group, index: index, filter: filter, inventory: inventory, masters: masters, work: work,
        into: &merge, outcome: &outcome)
    }
    guard !merge.calibrated.isEmpty else {
      outcome.error = "\(filter): every calibration group failed — see the group warnings"
      return outcome
    }
    if merge.calibrated.count == 1 {
      try await promoteLone(merge.calibrated[0], filter: filter, out: out, into: &outcome)
      return outcome
    }
    let anchor = NightPlan.anchorGroup(merge.nights, anchorNight: anchorNight)
    if settings.photometricNormalisation && merge.photometry.count > 1 {
      normalise(&merge, anchor: anchor, into: &outcome)
    }
    try await mergeAndStack(merge, anchor: anchor, filter: filter, work: work, out: out, into: &outcome)
    return outcome
  }

  /// One night: linked, calibrated with its own masters (`calibrate_single` for a lone frame),
  /// BAYERPAT stripped, parity-corrected. A night that fails costs only its own frames.
  private func calibrate(
    _ group: FrameSet, index: Int, filter: String, inventory: Inventory, masters: [CalibrationMaster],
    work: URL, into merge: inout Merge, outcome: inout ChannelOutcome
  ) async throws {
    let label = group.key.session.isEmpty ? "current session" : group.key.session
    let folder = work.appendingPathComponent("light_\(ChannelTag.sanitize(filter))_g\(index)")
    let selection = CalibrationMatcher.select(group, in: inventory, masters: masters)
    let light = ChannelStacker.Light(
      folder: folder, masters: ChannelStacker.masters(selection, frames: group.frames),
      ingest: SirilIngest(paths: group.frames.map(\.path)))
    do {
      try? FileManager.default.removeItem(at: folder)
      try MasterBuilder.link(group.frames.map(\.path), into: folder)
      let script =
        group.count == 1
        ? SirilScripts.calibrateSingle(seq: light.seq, masters: light.masters, ingest: light.ingest)
        : SirilScripts.calibrateOnly(seq: light.seq, masters: light.masters, ingest: light.ingest)
      try await stacker.run(script, in: folder)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      stacker.warn(
        "\(label) · \(filter): group failed, its \(group.count) frame(s) skipped — \(ChannelStacker.describe(error))",
        into: &outcome)
      return
    }
    let paths = (1...group.count).map { light.frame(light.calibrated, $0).path }
    for path in paths { try? FITSFile.stripKeyword("BAYERPAT", at: URL(fileURLWithPath: path)) }
    let parity = try await parity.correct(group, folder: folder, base: light.calibrated)
    if !parity.note.isEmpty { outcome.selection.notes.append(parity.note) }
    merge.spans.append(merge.calibrated.count..<(merge.calibrated.count + paths.count))
    merge.calibrated += paths
    merge.frames += group.frames
    merge.nights.append(group)
    merge.photometry.append(Self.photometryGroup(group, filter: filter, paths: paths))
    outcome.inputFrames += group.count
  }

  /// The photometric group of a night (`buildPhotomGroup`).
  static func photometryGroup(_ group: FrameSet, filter: String, paths: [String]) -> PhotomGroup {
    let key = group.key
    var label = "\(filter) g\(key.gain) o\(key.offset) \(key.exposureMs)ms t\(key.tempBucketC)C"
    if !key.session.isEmpty { label = key.session + " · " + label }
    let meta = PhotomMeta(
      exposureMs: key.exposureMs, gain: key.gain,
      gainKnown: !group.frames.isEmpty && group.frames.allSatisfy(\.hasGain),
      instrument: group.frames.first { !$0.instrument.isEmpty }?.instrument ?? "",
      creator: group.frames.first { !$0.creator.isEmpty }?.creator ?? "")
    return PhotomGroup(paths: paths, label: label, meta: meta, session: key.session)
  }

  /// The anchor night is the reference; every other night is mapped onto it.
  private func normalise(_ merge: inout Merge, anchor: Int, into outcome: inout ChannelOutcome) {
    merge.photometry[anchor].isReference = true
    let (records, notes) = PhotometricNormaliser.normalise(merge.photometry)
    outcome.photometry = records
    outcome.selection.notes += notes
  }

  /// A channel whose whole integration is one calibrated frame (`promoteLoneCalibrated`).
  private func promoteLone(_ frame: String, filter: String, out: URL, into outcome: inout ChannelOutcome)
    async throws
  {
    stacker.warn(
      "\(filter): only 1 calibrated frame in total — using it as the channel master (no registration/stacking)",
      into: &outcome)
    let master = out.appendingPathComponent("master_" + ChannelTag.of(filter)).appendingPathExtension("fits")
    try FileReplace.copy(URL(fileURLWithPath: frame), over: master)
    outcome.stackedFrames = 1
    outcome.masterPath = master.path
    try? FITSFile.stripKeyword("BAYERPAT", at: master)
  }
}
