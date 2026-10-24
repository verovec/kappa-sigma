package import Foundation
package import ProjectKit

/// Settings › Storage (card 0114): the retention policy and the « Remind in 7 days » of its
/// launch sheet, in the app's defaults (the stacks kept are recorded in their projects).
package nonisolated struct RetentionSetting {
  private static let modeKey = "retention.mode"
  private static let daysKey = "retention.days"
  private static let snoozeKey = "retention.snoozedUntil"
  /// The days a policy may be set to.
  package static let dayRange = 7...365
  private let defaults: UserDefaults

  /// The setting stored in `defaults`.
  package init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The policy: Ask after 30 days until the user changes it.
  package var policy: RetentionPolicy {
    get {
      let stored = defaults.integer(forKey: Self.daysKey)
      return RetentionPolicy(
        mode: defaults.string(forKey: Self.modeKey).flatMap(RetentionPolicy.Mode.init) ?? .ask,
        days: Self.dayRange.contains(stored) ? stored : RetentionPolicy.defaultDays)
    }
    nonmutating set {
      defaults.set(newValue.mode.rawValue, forKey: Self.modeKey)
      defaults.set(
        min(max(newValue.days, Self.dayRange.lowerBound), Self.dayRange.upperBound),
        forKey: Self.daysKey)
    }
  }

  /// Until when (Unix ms) the launch sheet is not shown; 0 = not snoozed.
  package var snoozedUntil: Int64 {
    get { Int64(defaults.double(forKey: Self.snoozeKey)) }
    nonmutating set { defaults.set(Double(newValue), forKey: Self.snoozeKey) }
  }
}
