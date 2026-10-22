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

  /// `value` after one arrow press, on the grid of the fine step: three presses of 0.0001 read
  /// 0.0003, never 0.00030000000000000003 (the field shows the value applied, R2).
  package func moved(_ value: Double, forward: Bool, fine: Bool) -> Double {
    let grid = (1 / self.fine).rounded()
    return ((value + delta(forward: forward, fine: fine)) * grid).rounded() / grid
  }

  /// ⌥-drag: the value moves a tenth of the pointer's travel since the gearing began.
  ///
  /// `anchor` is the value then, `start` the pointer then: the thumb stays on the value and the
  /// pointer runs ahead of it. Re-anchoring when ⌥ changes mid-drag keeps the value continuous.
  package func fineDragValue(anchor: Double, start: Double, pointer: Double) -> Double {
    anchor + (pointer - start) / 10
  }
}
