internal import Foundation
internal import SwiftUI

/// The modifier behind `.accessible(_:label:)`: label, identifier, audit entry.
struct AccessibleControl: ViewModifier {
  enum Label {
    case resource(LocalizedStringResource)
    case verbatim(String)
  }

  let id: AccessibilityID?
  let label: Label
  /// What VoiceOver reads after the label (a help button's summary), if any.
  let hint: Label?
  @Environment(\.locale) private var locale
  @Environment(\.guideTarget) private var guideTarget

  func body(content: Content) -> some View {
    let text = resolve(label)
    let hint = hint.map(resolve)
    let highlighted = id != nil && id == guideTarget
    return
      content
      // The first-stack guide's ring around the control its step points at (card 0061).
      .overlay {
        if highlighted {
          RoundedRectangle(cornerRadius: DesignMetrics.radiusSmall)
            .stroke(Color.accentColor, lineWidth: 2).padding(-DesignMetrics.spacingXXS)
            .allowsHitTesting(false)
        }
      }
      .accessibilityLabel(Text(verbatim: text))
      .accessibilityHint(ifPresent: hint)
      .accessibilityIdentifier(id?.rawValue ?? "")
      // Appended, never replacing: a control inside an announced container keeps its entry.
      .transformPreference(AccessibilityAudit.Key.self) {
        $0.append(
          AccessibilityAudit.Entry(
            id: id?.rawValue ?? "", label: text, highlighted: highlighted, hint: hint))
      }
  }

  private func resolve(_ label: Label) -> String {
    switch label {
    case .verbatim(let text):
      return text
    case .resource(var resource):
      resource.locale = locale
      return String(localized: resource)
    }
  }
}

extension View {
  /// `accessibilityHint` only when there is one: a control's own hint is never blanked.
  @ViewBuilder fileprivate func accessibilityHint(ifPresent hint: String?) -> some View {
    if let hint { accessibilityHint(Text(verbatim: hint)) } else { self }
  }
}
