/// Why a row cannot run as set (card 0135): a catalog reason, about `subject` (a layer's panel
/// name) when the reason does not say it all — the panel's counterpart of `Suggestion`.
package struct RowNote: Equatable, Sendable {
  /// The reason, an English key of the catalog.
  package let reason: String
  /// What it is about, shown as is next to it; nil for a reason that says it all.
  package let subject: String?

  /// A note `reason` about `subject`.
  package init(reason: String, subject: String? = nil) {
    self.reason = reason
    self.subject = subject
  }
}
