package import Foundation
package import SwiftUI

/// How an interactive control is announced (card 0079): every button, slider, field, toggle or
/// picker of the shared components and the workspace goes through `.accessible(_:label:)`.
///
/// SwiftUI builds its accessibility tree only for a connected assistive client, so a test cannot
/// walk it; instead each control reports its id and label through `AccessibilityAudit.Key`, and
/// `AccessibilityAuditTests` checks what a hosted view reported (plus a source gate that counts
/// raw controls against `.accessible` calls).
package enum AccessibilityAudit {
  /// One control as it announced itself.
  package struct Entry: Equatable, Sendable {
    /// Its identifier.
    package let id: String
    /// Its label in the view's language (empty: VoiceOver would read nothing useful).
    package let label: String

    /// The entry of a control identified by `id` and labelled `label`.
    package init(id: String, label: String) {
      self.id = id
      self.label = label
    }
  }

  /// The controls of a view, collected for the audit.
  package struct Key: PreferenceKey {
    package static let defaultValue: [Entry] = []

    package static func reduce(value: inout [Entry], nextValue: () -> [Entry]) {
      value += nextValue()
    }
  }

  /// What is wrong with `entries`: an empty label, an empty or repeated identifier.
  package static func problems(_ entries: [Entry]) -> [String] {
    var problems: [String] = []
    var seen: Set<String> = []
    for entry in entries {
      if entry.id.isEmpty { problems.append("a control without identifier (« \(entry.label) »)") }
      if entry.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        problems.append("\(entry.id): no label")
      }
      if !entry.id.isEmpty, !seen.insert(entry.id).inserted {
        problems.append("\(entry.id): identifier used twice")
      }
    }
    return problems
  }
}

extension View {
  /// Labels this control for VoiceOver with `label` and identifies it with `id`, and reports both
  /// to the accessibility audit.
  package func accessible(_ id: AccessibilityID?, label: LocalizedStringResource) -> some View {
    modifier(AccessibleControl(id: id, label: .resource(label)))
  }

  /// Labels this control with `label` (already in the view's language, a glossary term for
  /// instance) and identifies it with `id`.
  package func accessible(_ id: AccessibilityID?, verbatim label: String) -> some View {
    modifier(AccessibleControl(id: id, label: .verbatim(label)))
  }
}
