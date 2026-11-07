/// How many steps a held ↑/↓ moves per key event (card 0179): one per press, then 2, 5 and 10
/// per auto-repeat as the key stays down, by eights of repeats.
///
/// Counted in repeats, never in time: the same presses always move the value the same distance,
/// and the tiers follow the user's key-repeat rate (about 0.7 s per tier at the macOS default).
/// A release, or a new press, starts again at one step.
package struct ArrowRepeat: Equatable, Sendable {
  /// What the key did.
  package enum Phase: Sendable {
    case down, `repeat`, up
  }

  /// The steps per event, tier by tier.
  package static let tiers = [1, 2, 5, 10]
  /// Repeats spent in each tier before the next.
  package static let repeatsPerTier = 8

  private var repeats = 0

  /// A key that is not held.
  package init() {}

  /// The steps one key event moves: ↑/↓ (`accelerating`) 1 on a press then the current tier on
  /// each repeat, ←/→ one per press or repeat, never faster; `nil` on a release, which moves
  /// nothing.
  package mutating func steps(_ phase: Phase, accelerating: Bool) -> Int? {
    if accelerating { return multiplier(phase) }
    return phase == .up ? nil : Self.tiers[0]
  }

  private mutating func multiplier(_ phase: Phase) -> Int? {
    switch phase {
    case .down:
      repeats = 0
      return Self.tiers[0]
    case .repeat:
      repeats += 1
      return Self.tiers[min(repeats / Self.repeatsPerTier, Self.tiers.count - 1)]
    case .up:
      repeats = 0
      return nil
    }
  }
}
