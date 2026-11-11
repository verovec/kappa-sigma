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

  /// The estimate of a run of `inventory` with `settings`; throws the plan's own refusal
  /// (no lights, several objects, mono + colour).
  ///
  /// With `cache` (card 0191) a bucket's frames are kept between runs instead of going with
  /// their lane: every frame not kept yet is downloaded once and stays, so the run needs the
  /// largest lane's copies plus all of those downloads — and nothing for a frame already kept.
  package init(
    _ inventory: Inventory, settings: PreprocessSettings, cache: RemoteFrameCache? = nil
  ) throws {
    let plan = try Preprocessor.plan(inventory)
    let lanes = plan.channels.map { lane, groups in
      (lane, Self.laneBytes(groups, flatten: settings.flattenBackground, raw: cache == nil))
    }
    // Ties broken by name: the same scan always names the same lane.
    let peak = lanes.max { ($0.1, $1.0) < ($1.1, $0.0) }
    if let cache {
      let downloads = inventory.sets.reduce(Int64(0)) { total, set in
        total + Self.rawRemoteBytes(set) { !cache.holds($0.path) }
      }
      bytes = (peak?.1 ?? 0) + downloads
      lane = peak?.0 ?? ""
      return
    }
    // Step 1 downloads a bucket's raw calibration frames into `work/masters/cal_<name>`, one set
    // at a time, each removed when its master is built (card 0154): the largest of them can
    // exceed a lane, and card 0098's check has to see it.
    let calibration = inventory.sets.filter { $0.key.type != .light }
      .map { (Self.rawRemoteBytes($0), $0.key.id) }
    let heaviestSet = calibration.max { ($0.0, $1.1) < ($1.0, $0.1) }
    if let heaviestSet, heaviestSet.0 > (peak?.1 ?? 0) {
      bytes = heaviestSet.0
      lane = heaviestSet.1
      return
    }
    bytes = peak?.1 ?? 0
    lane = peak?.0 ?? ""
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
  /// `raw` adds the bucket frames the lane downloads into its own folder; a run that keeps them
  /// elsewhere (card 0191) counts them once for the whole run instead.
  package static func laneBytes(_ groups: [FrameSet], flatten: Bool, raw: Bool = true) -> Int64 {
    // `GroupedChannelStacker.register` flattens only a lane of several nights.
    let copies: Int64 = flatten && groups.count > 1 ? 3 : 2
    // The frames a lane downloads sit in its folder beside the copies Siril writes.
    let raw =
      !raw
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
