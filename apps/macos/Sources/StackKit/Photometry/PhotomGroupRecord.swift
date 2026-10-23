/// What normalisation did to one group (`photom.GroupRecord`), as the run records it.
package struct PhotomGroupRecord: Codable, Equatable, Sendable {
  package var sessionID: Int
  package var session: String
  package var label: String
  package var scale = 1.0
  package var offset = 0.0
  package var residual = 0.0
  package var frames: Int
  package var clamped = false
  package var metaDisagree = false
  package var metaSeeded = false
  package var isReference = false
  /// The group's frames were rewritten.
  package var applied = false
  package var method: PhotomTransform.Method?
  /// The fitted transform would have clipped the sky: the recorded one is the degraded one.
  package var reverted = false
  /// The median saturated fraction of the probed frames (0: the median curve does not carry it).
  package var saturatedFraction = 0.0
  /// Where the saturation plateau lands after the transform (`scale · 0.97 + offset`).
  package var saturationCeiling = 0.0

  /// The measured-but-not-applied record of `group`.
  init(skipping group: PhotomGroup) {
    sessionID = group.sessionID
    session = group.session
    label = group.label
    frames = group.paths.count
  }
}
