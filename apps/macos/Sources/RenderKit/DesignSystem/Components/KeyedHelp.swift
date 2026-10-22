package import SwiftUI

/// A `HelpContent` with the identifier of its « ? »: what a header or an empty state takes, so
/// the content and the key never travel apart (card 0086).
package struct KeyedHelp {
  /// The summary and the popover's view.
  package let content: HelpContent
  /// The button's identifier.
  package let key: AccessibilityID

  /// `content` behind the button `key`.
  package init(_ content: HelpContent, key: AccessibilityID) {
    self.content = content
    self.key = key
  }

  /// The « ? ».
  @MainActor package var button: some View {
    HelpButton(summary: content.summary, key: key) { content.content() }
  }
}
