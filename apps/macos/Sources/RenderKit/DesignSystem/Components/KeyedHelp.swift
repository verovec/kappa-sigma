package import SwiftUI

/// A `HelpContent` with the identifier (and the VoiceOver label) of its « ? »: the one way a
/// button is wired, so the content and the key never travel apart (card 0086).
package struct KeyedHelp {
  /// The summary and the popover's view.
  package let content: HelpContent
  /// The button's identifier.
  package let key: AccessibilityID
  /// What VoiceOver calls the button.
  package let label: HelpButtonLabel

  /// `content` behind the button `key`, labelled `label`.
  package init(_ content: HelpContent, key: AccessibilityID, label: HelpButtonLabel = .help) {
    self.content = content
    self.key = key
    self.label = label
  }

  /// The « ? ».
  @MainActor package var button: some View {
    HelpButton(summary: content.summary, label: label, key: key) { content.content() }
  }
}
