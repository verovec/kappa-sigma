internal import Foundation

/// A parameter's keyboard and fine-drag step (cards 0085, 0179).
///
/// Arrows move one `coarse` step, ⇧-arrows (or ⌥-arrows) and ⌥-drag a `fine` one, a tenth of it
/// unless the value is a whole number. A held ↑/↓ moves several steps per repeat (`ArrowRepeat`).
/// A panel may declare its own (`wholeNumber` for counts and whole pixels); every other row
/// takes `default(for:)`.
package struct ParameterStep: Equatable, Sendable {
  /// One arrow press.
  package let coarse: Double

  /// A ⇧-arrow press, and the gearing of an ⌥-drag.
  package let fine: Double

  /// A whole-number step: no fraction to give, ⇧ and ⌥-drag move whole steps too, and a press
  /// lands on the next whole number (3.4 ↑ reads 4).
  package let whole: Bool

  /// A step of `coarse` per arrow and a tenth of it with ⇧ or ⌥.
  package init(_ coarse: Double) {
    self.coarse = coarse
    fine = coarse / 10
    whole = false
  }

  private init(whole coarse: Double) {
    self.coarse = coarse
    fine = coarse
    whole = true
  }

  /// One per press, ⇧ too, landing on whole numbers: a count, a degree, whole pixels.
  package static let wholeNumber = Self(whole: 1)

  /// The step of a decimal row whose panel declares none.
  ///
  /// About a hundredth of `range` rounded to a decade (0…1 → 0.01, −5…5 → 0.1, 0…64 → 1), so a
  /// value keeps the decimals it is written with. An empty range steps by one.
  package static func `default`(for range: ClosedRange<Double>) -> Self {
    let span = range.upperBound - range.lowerBound
    guard span.isFinite, span > 0 else { return Self(1) }
    return Self(decade(Int((log10(span / 100)).rounded())))
  }

  /// 10ⁿ as the closest double: 1 / 10⁻ⁿ for a negative n (pow(10, −n) may miss 0.01).
  private static func decade(_ exponent: Int) -> Double {
    exponent < 0 ? 1 / pow(10, Double(-exponent)) : pow(10, Double(exponent))
  }

  /// The change an arrow press makes: `coarse` (`fine` with ⇧ or ⌥), negative backwards.
  package func delta(forward: Bool, fine: Bool) -> Double {
    (forward ? 1 : -1) * (fine ? self.fine : coarse)
  }

  /// `value` after `times` presses: one, or a held ↑/↓'s tier.
  ///
  /// Rounded to the decimals of the fine step or of `value`, whichever has more: three presses
  /// of 0.0001 read 0.0003, never 0.00030000000000000003, and a typed 0.25 keeps its two
  /// decimals (the field shows the value applied, R2). A whole step lands on whole numbers:
  /// 3.4 ↑ reads 4, ↓ reads 3.
  package func moved(_ value: Double, forward: Bool, fine: Bool, times: Int = 1) -> Double {
    if whole {
      let count = coarse * Double(times)
      return forward ? value.rounded(.down) + count : value.rounded(.up) - count
    }
    let scale = max(Self.decimalScale(of: self.fine), Self.decimalScale(of: value))
    let delta = delta(forward: forward, fine: fine) * Double(times)
    return ((value + delta) * scale).rounded() / scale
  }

  /// 10ⁿ for the n decimals `step` is written with (1 for a whole step, at most 10¹²).
  static func decimalScale(of step: Double) -> Double {
    var scale = 1.0
    while scale < 1e12 {
      let scaled = step.magnitude * scale
      if abs(scaled - scaled.rounded()) <= 1e-9 * max(scaled, 1) { break }
      scale *= 10
    }
    return scale
  }

  /// ⌥-drag: the value moves a tenth of the pointer's travel since the gearing began (all of it
  /// for a whole step, which has no tenth to give, rounded to a whole number).
  ///
  /// `anchor` is the value then, `start` the pointer then: the thumb stays on the value and the
  /// pointer runs ahead of it. Re-anchoring when ⌥ changes mid-drag keeps the value continuous.
  package func fineDragValue(anchor: Double, start: Double, pointer: Double) -> Double {
    whole ? pointer.rounded() : anchor + (pointer - start) / 10
  }
}
