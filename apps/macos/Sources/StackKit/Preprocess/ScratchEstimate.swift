package import Foundation
internal import ProjectKit

/// The scratch a run's Siril work folder peaks at, estimated from its plan before Siril starts
/// (card 0098).
///
/// Lanes run one after another and each removes its folders when it ends
/// (`ChannelStacker.stack`, `GroupedChannelStacker.stack`), so the peak is the largest lane.
/// A lane writes each light as a 32-bit copy per Siril step: calibrated (`pp_`), registered
/// (`r_`), plus the flattened copy (`flat_`) when a multi-night lane flattens before registering,
/// plus the converted copy of a capture that is not FITS.
/// A colour light is debayered at calibration: three planes. Pinned against card 0058's measured
/// peaks (M 31 80.6 GB, IC 1848 106 GB) within 10 %.
///
/// A lane whose frames live in a bucket (card 0154) also holds their raw bytes while it runs:
/// they are downloaded into the lane's folder and go with it, so they are added to that lane's
/// own peak — never to the whole run's.
package struct ScratchEstimate: Equatable, Sendable {
  /// The peak, in bytes.
  package var bytes: Int64
  /// The lane that sets it.
  package var lane: String
  /// The part of `bytes` that stays after the run (card 0191).
  ///
  /// The bucket frames it downloads and keeps; zero for a run that downloads into its lanes.
  package var keptBytes: Int64 = 0

  /// The estimate of a run of `inventory` with `settings`; throws the plan's own refusal
  /// (no lights, several objects, mono + colour).
  ///
  /// `kept` says the run keeps its bucket frames between runs (card 0191) and names the frames
  /// already kept: instead of going with their lane, the lights not kept yet are downloaded once
  /// and stay, so the run needs the largest lane's copies plus all of those — and nothing for a
  /// frame already kept. Calibration frames are downloaded only for a master that must be built,
  /// which the plan does not say here: as before, their largest set not kept yet is counted.
  package init(
    _ inventory: Inventory, settings: PreprocessSettings, kept: Set<String>? = nil
  ) throws {
    let plan = try Preprocessor.plan(inventory)
    let lanes = plan.channels.map { lane, groups in
      (lane, Self.laneBytes(groups, flatten: settings.flattenBackground, downloads: kept == nil))
    }
    // Ties broken by name: the same scan always names the same lane.
    let peak = lanes.max { ($0.1, $1.0) < ($1.1, $0.0) }
    // Step 1 downloads a bucket's raw calibration frames into `work/masters/cal_<name>`, one set
    // at a time, each removed when its master is built (card 0154): the largest of them can
    // exceed a lane, and card 0098's check has to see it.
    let calibration = inventory.sets.filter { $0.key.type != .light }
      .map { (Self.rawRemoteBytes($0) { kept?.contains($0.path) != true }, $0.key.id) }
    let heaviestSet = calibration.max { ($0.0, $1.1) < ($1.0, $0.1) }
    if let kept {
      let lights = inventory.sets.filter { $0.key.type == .light }.reduce(Int64(0)) { total, set in
        total + Self.rawRemoteBytes(set) { !kept.contains($0.path) }
      }
      keptBytes = lights + (heaviestSet?.0 ?? 0)
      bytes = (peak?.1 ?? 0) + keptBytes
      lane = peak?.0 ?? ""
      return
    }
    if let heaviestSet, heaviestSet.0 > (peak?.1 ?? 0) {
      bytes = heaviestSet.0
      lane = heaviestSet.1
      return
    }
    bytes = peak?.1 ?? 0
    lane = peak?.0 ?? ""
  }

  /// What a queue of runs needs, one after another (card 0191).
  ///
  /// The largest of their peaks without what each keeps, plus everything they keep — a run's
  /// downloads are still there when the next one starts. For runs that keep nothing, the
  /// largest peak.
  package static func queued(_ estimates: [Self]) -> Int64? {
    guard let peak = estimates.map({ $0.bytes - $0.keptBytes }).max() else { return nil }
    return peak + estimates.reduce(0) { $0 + $1.keptBytes }
  }

  /// Refuses a run whose peak exceeds `room`, the bytes left on the volume of `folder`
  /// (`PreprocessError.scratchFull`); a volume that does not say (`nil`) refuses nothing.
  package func check(room: Int64?, folder: URL) throws {
    guard let room, bytes > room else { return }
    throw PreprocessError.scratchFull(neededBytes: bytes, availableBytes: room, folder: folder.path)
  }

  /// One lane: its lights × the copies its steps write × one light's bytes, plus the copy
  /// `convert` writes of a night that is not FITS (a camera raw), before calibration.
  ///
  /// `downloads` adds the bucket frames the lane downloads into its own folder; a run that
  /// keeps them elsewhere (card 0191) counts them once for the whole run instead.
  package static func laneBytes(_ groups: [FrameSet], flatten: Bool, downloads: Bool = true)
    -> Int64
  {
    // `GroupedChannelStacker.register` flattens only a lane of several nights.
    let copies: Int64 = flatten && groups.count > 1 ? 3 : 2
    // The frames a lane downloads sit in its folder beside the copies Siril writes.
    let raw =
      !downloads
      ? 0
      : groups.reduce(Int64(0)) { total, group in
        total + Self.rawRemoteBytes(group)
      }
    return groups.reduce(0) { total, group in
      let converted = SirilIngest(paths: group.frames.map(\.path)) == .convert
      return group.frames.reduce(total) { sum, frame in
        sum + copies * Self.frameBytes(frame) + (converted ? Self.ingestBytes(frame) : 0)
      }
    } + raw
  }

  /// The bytes a group's frames of a bucket are downloaded as (card 0154).
  ///
  /// Their stored size, which for a 16-bit capture is half a 32-bit copy; a frame of this Mac
  /// costs nothing, being symlinked where it stands.
  ///
  /// `counted` leaves out the frames it refuses (those a cache already keeps).
  package static func rawRemoteBytes(
    _ group: FrameSet, counted: (CaptureFrame) -> Bool = { _ in true }
  ) -> Int64 {
    group.frames.reduce(0) { total, frame in
      guard ProjectSource.remoteParts(of: frame.path) != nil, counted(frame) else { return total }
      return total + Int64(frame.width) * Int64(frame.height) * Int64(max(frame.channels, 1)) * 2
    }
  }

  /// The 32-bit copy `convert` writes of a light, as captured (a mosaic stays one plane).
  static func ingestBytes(_ frame: CaptureFrame) -> Int64 {
    Int64(frame.width) * Int64(frame.height) * Int64(max(frame.channels, 1)) * 4
  }

  /// One 32-bit copy of `frame` as Siril writes it (`set32bits`): a colour frame debayered.
  static func frameBytes(_ frame: CaptureFrame) -> Int64 {
    let planes: Int64 = frame.isColor ? 3 : 1
    return Int64(frame.width) * Int64(frame.height) * planes * 4
  }
}
