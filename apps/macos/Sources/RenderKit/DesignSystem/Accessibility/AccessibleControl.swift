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
  @Environment(\.locale) private var locale

  func body(content: Content) -> some View {
    let text = resolved
    return
      content
      .accessibilityLabel(Text(verbatim: text))
      .accessibilityIdentifier(id?.rawValue ?? "")
      // Appended, never replacing: a control inside an announced container keeps its entry.
      .transformPreference(AccessibilityAudit.Key.self) {
        $0.append(AccessibilityAudit.Entry(id: id?.rawValue ?? "", label: text))
      }
  }

  private var resolved: String {
    switch label {
    case .verbatim(let text):
      return text
    case .resource(var resource):
      resource.locale = locale
      return String(localized: resource)
    }
  }
}
