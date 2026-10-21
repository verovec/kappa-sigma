/// What the app found of a host tool at the path it looked at.
package enum ToolStatus: Equatable, Sendable {
  /// Usable; `version` when the tool reports one.
  case found(path: String, version: String?)
  /// Nothing usable there: the process that needs it is greyed with an install card (R2).
  case missing(path: String)
  /// Installed, but older than the version the app's scripts need.
  case tooOld(path: String, version: String)

  /// The path that was looked at.
  package var path: String {
    switch self {
    case .found(let path, _), .missing(let path), .tooOld(let path, _): path
    }
  }

  /// Whether a process may run the tool.
  package var isUsable: Bool {
    if case .found = self { true } else { false }
  }
}
