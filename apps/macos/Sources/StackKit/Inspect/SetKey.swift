/// What makes frames interchangeable (`inspect.SetKey`): only the fields that matter for a type
/// are set (darks carry no filter or object; bias no exposure).
package struct SetKey: Hashable, Sendable {
  package var type: FrameType
  package var object: String
  package var filter: String
  package var exposureMs: Int
  package var gain: Int
  package var offset: Int
  /// Median temperature of the cluster, whole °C (lights, darks, dark-flats only).
  package var tempBucketC: Int
  package var bin: Int
  /// Capture night, set only for lights and flats of a scan spanning several known nights.
  package var session: String
  /// One-shot colour, kept apart from mono frames of the same settings.
  package var color: Bool

  /// A key with the given fields, the rest at zero.
  package init(
    type: FrameType, object: String = "", filter: String = "", exposureMs: Int = 0, gain: Int = 0,
    offset: Int = 0, tempBucketC: Int = 0, bin: Int = 0, session: String = "", color: Bool = false
  ) {
    self.type = type
    self.object = object
    self.filter = filter
    self.exposureMs = exposureMs
    self.gain = gain
    self.offset = offset
    self.tempBucketC = tempBucketC
    self.bin = bin
    self.session = session
    self.color = color
  }

  /// The key a frame groups under (`setKeyFor`), before its temperature cluster is known.
  init(frame: CaptureFrame, splitNights: Bool) {
    self.init(
      type: frame.type, gain: frame.gain, offset: frame.offset, bin: frame.binX,
      color: frame.isColor)
    switch frame.type {
    case .light:
      object = frame.object
      filter = frame.filter
      exposureMs = frame.exposureMs
    case .dark, .darkFlat:
      exposureMs = frame.exposureMs
    case .flat:
      filter = frame.filter
      exposureMs = frame.exposureMs
    case .bias, .video, .unknown:
      break
    }
    if splitNights && (frame.type == .light || frame.type == .flat) { session = frame.session }
  }

  /// The stable exclusion token users' choices are stored under; the format is a contract.
  /// `i0` is the legacy ISO field (phone raws are not ported). `color` is deliberately absent.
  package var id: String {
    "\(type.rawValue)|\(object)|\(filter)|e\(exposureMs)|g\(gain)o\(offset)b\(bin)|i0"
      + "|t\(tempBucketC)|s:\(session)"
  }

  /// Display order: type, object, filter, night, exposure, gain, offset — then the fields Go left
  /// to an unstable sort (bin, colour, temperature) so the order is deterministic.
  static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.type.setOrder != rhs.type.setOrder { return lhs.type.setOrder < rhs.type.setOrder }
    if lhs.object != rhs.object { return lhs.object < rhs.object }
    if lhs.filter != rhs.filter { return lhs.filter < rhs.filter }
    if lhs.session != rhs.session { return lhs.session < rhs.session }
    let left = [lhs.exposureMs, lhs.gain, lhs.offset, lhs.bin, lhs.color ? 1 : 0, lhs.tempBucketC]
    let right = [rhs.exposureMs, rhs.gain, rhs.offset, rhs.bin, rhs.color ? 1 : 0, rhs.tempBucketC]
    return left.lexicographicallyPrecedes(right)
  }
}
