package import Foundation
package import SwiftUI

/// What a « ? » offers (card 0086): the one-line `summary` for the tooltip and VoiceOver, and
/// the full `content` for the popover — a view the caller builds, so RenderKit never imports
/// HelpKit (the app renders its Markdown with `HelpText`).
package struct HelpContent {
  /// One line: shown on hover, read as the button's hint.
  package let summary: LocalizedStringResource
  /// The popover's view.
  package let content: () -> AnyView

  /// Help summarised by `summary`, detailed by `content`.
  package init<Content: View>(
    summary: LocalizedStringResource, @ViewBuilder content: @escaping () -> Content
  ) {
    self.summary = summary
    self.content = { AnyView(content()) }
  }
}
