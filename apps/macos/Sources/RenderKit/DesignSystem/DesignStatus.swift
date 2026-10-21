/// A verdict's kind: its colour and its icon, so a status is never told by colour alone.
package enum DesignStatus: CaseIterable, Sendable {
  /// Nothing to do.
  case ok
  /// Worth a look.
  case attention
  /// Failed.
  case error
  /// Not there (a missing tool, a value not measured).
  case unavailable

  /// The colour token.
  package var token: DesignColor {
    switch self {
    case .ok: .statusOK
    case .attention: .statusAttention
    case .error: .statusError
    case .unavailable: .statusUnavailable
    }
  }

  /// The SF Symbol shown next to the words.
  package var systemImage: String {
    switch self {
    case .ok: "checkmark.circle.fill"
    case .attention: "exclamationmark.triangle.fill"
    case .error: "xmark.octagon.fill"
    case .unavailable: "minus.circle"
    }
  }
}
