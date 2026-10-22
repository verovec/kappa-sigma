package import Foundation
package import SwiftUI

/// The « ? » of the design system (card 0086, R3: help on demand): hover shows the one-line
/// `summary`, click opens an anchored, transient popover with `content` — Esc or a click outside
/// closes it, nothing is modal.
///
/// Identified by `key` (`AccessibilityID.help` for a stage or a value, `.parameter(_, .help)` in a
/// `ParameterRow`); the summary is the button's accessibility hint.
package struct HelpButton<Content: View>: View {
  private let summary: LocalizedStringResource
  private let label: HelpButtonLabel
  private let key: AccessibilityID
  private let content: () -> Content
  @State private var shown = false

  /// A help button summarised by `summary` (labelled `label` for VoiceOver), identified by `key`.
  package init(
    summary: LocalizedStringResource, label: HelpButtonLabel = .help, key: AccessibilityID,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.summary = summary
    self.label = label
    self.key = key
    self.content = content
  }

  package var body: some View {
    Button {
      // Opens only: a click outside (the « ? » included) already closed the transient popover
      // on mouse-down, a toggle here would reopen it on mouse-up.
      shown = true
    } label: {
      Image(systemName: "questionmark.circle")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(DesignColor.textSecondary.color)
    .help(Text(summary))
    .accessible(key, label: label.resource, hint: summary)
    .popover(isPresented: $shown, arrowEdge: .bottom) {
      HelpPopover(close: { shown = false }, content: content)
    }
  }
}

/// What a « ? » popover shows: the caller's content at the popover's width; Esc inside it
/// closes it (a transient popover also closes on a click outside).
package struct HelpPopover<Content: View>: View {
  private let close: () -> Void
  private let content: () -> Content

  /// The popover around `content`, closed by `close`.
  package init(close: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
    self.close = close
    self.content = content
  }

  package var body: some View {
    content()
      .padding(DesignMetrics.spacingM)
      .frame(width: 320, alignment: .leading)
      .onExitCommand(perform: close)
  }
}
