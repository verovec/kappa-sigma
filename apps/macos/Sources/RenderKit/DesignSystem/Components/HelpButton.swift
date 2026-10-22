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
  private let external: Binding<Bool>?
  private let content: () -> Content
  @State private var shown = false

  /// A help button summarised by `summary` (labelled `label` for VoiceOver), identified by
  /// `key`; `isPresented` lets a host drive the popover, else the button keeps its own state.
  package init(
    summary: LocalizedStringResource, label: HelpButtonLabel = .help, key: AccessibilityID,
    isPresented: Binding<Bool>? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.summary = summary
    self.label = label
    self.key = key
    external = isPresented
    self.content = content
  }

  private var presentation: Binding<Bool> { external ?? $shown }

  package var body: some View {
    Button {
      presentation.wrappedValue.toggle()
    } label: {
      Image(systemName: "questionmark.circle")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(DesignColor.textSecondary.color)
    .help(Text(summary))
    .accessible(key, label: label.resource, hint: summary)
    .popover(isPresented: presentation, arrowEdge: .bottom) {
      content()
        .padding(DesignMetrics.spacingM)
        .frame(width: 320, alignment: .leading)
        // Esc inside the popover; a transient popover also closes on a click outside.
        .onExitCommand { presentation.wrappedValue = false }
    }
  }
}
