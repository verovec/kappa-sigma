package import Foundation

/// What VoiceOver calls a `HelpButton` (card 0086).
package enum HelpButtonLabel: Sendable {
  /// « Help »: a stage, a value, a card.
  case help
  /// « Why this value? »: a parameter's default.
  case whyThisValue

  /// The words, in the view's language.
  package var resource: LocalizedStringResource {
    switch self {
    case .help: .renderKit("Help")
    case .whyThisValue: .renderKit("Why this value?")
    }
  }
}
