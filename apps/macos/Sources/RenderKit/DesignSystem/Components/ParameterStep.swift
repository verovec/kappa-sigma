/// A parameter's keyboard and fine-drag step (card 0085).
///
/// Arrows move one `coarse` step, ⇧-arrows (or ⌥-arrows) and ⌥-drag a tenth of it. Documented
/// per control by the panel that declares it.
package struct ParameterStep: Equatable, Sendable {
  /// One arrow press.
  package let coarse: Double

  /// A ⇧-arrow press, and the gearing of an ⌥-drag.
  package var fine: Double { coarse / 10 }

  /// A step of `coarse` per arrow.
  package init(_ coarse: Double) {
    self.coarse = coarse
  }

  /// The change an arrow press makes: `coarse` (`fine` with ⇧ or ⌥), negative backwards.
  package func delta(forward: Bool, fine: Bool) -> Double {
    (forward ? 1 : -1) * (fine ? self.fine : coarse)
  }

  /// ⌥-drag: the value moves a tenth of the pointer's travel since the gearing began.
  ///
  /// `anchor` is the value then, `start` the pointer then: the thumb stays on the value and the
  /// pointer runs ahead of it. Re-anchoring when ⌥ changes mid-drag keeps the value continuous.
  package func fineDragValue(anchor: Double, start: Double, pointer: Double) -> Double {
    anchor + (pointer - start) / 10
  }
}
