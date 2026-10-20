/// Frames sharing one photometric context — one night, one setup (`photom.Group`).
package struct PhotomGroup: Equatable, Sendable {
  package var paths: [String]
  /// `<night> · <filter> g<gain> o<offset> <exposure>ms t<temp>C`.
  package var label: String
  package var meta = PhotomMeta()
  /// The group the others are mapped onto.
  package var isReference = false
  package var sessionID = 0
  /// The capture night (`YYYY-MM-DD`; empty when undated).
  package var session = ""

  /// A group.
  package init(
    paths: [String], label: String, meta: PhotomMeta = PhotomMeta(), isReference: Bool = false,
    sessionID: Int = 0, session: String = ""
  ) {
    self.paths = paths
    self.label = label
    self.meta = meta
    self.isReference = isReference
    self.sessionID = sessionID
    self.session = session
  }
}
