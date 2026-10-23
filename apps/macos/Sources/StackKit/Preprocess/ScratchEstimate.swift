package import Foundation

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
package struct ScratchEstimate: Equatable, Sendable {
  /// The peak, in bytes.
  package var bytes: Int64
  /// The lane that sets it.
  package var lane: String

  /// The estimate of a run of `inventory` with `settings`; throws the plan's own refusal
  /// (no lights, several objects, mono + colour).
  package init(_ inventory: Inventory, settings: PreprocessSettings) throws {
    let plan = try Preprocessor.plan(inventory)
    let lanes = plan.channels.map { lane, groups in
      (lane, Self.laneBytes(groups, flatten: settings.flattenBackground))
    }
    // Ties broken by name: the same scan always names the same lane.
    let peak = lanes.max { ($0.1, $1.0) < ($1.1, $0.0) }
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
  static func laneBytes(_ groups: [FrameSet], flatten: Bool) -> Int64 {
    // `GroupedChannelStacker.register` flattens only a lane of several nights.
    let copies: Int64 = flatten && groups.count > 1 ? 3 : 2
    return groups.reduce(0) { total, group in
      let converted = SirilIngest(paths: group.frames.map(\.path)) == .convert
      return group.frames.reduce(total) { sum, frame in
        sum + copies * Self.frameBytes(frame) + (converted ? Self.ingestBytes(frame) : 0)
      }
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
