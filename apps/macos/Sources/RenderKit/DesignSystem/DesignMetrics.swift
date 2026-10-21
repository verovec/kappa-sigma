package import SwiftUI

/// Spacing, corner radii and the value font: the few numbers every panel shares.
package enum DesignMetrics {
  /// 2 pt: inside a badge.
  package static let spacingXXS: CGFloat = 2
  /// 4 pt: between a value and its unit.
  package static let spacingXS: CGFloat = 4
  /// 8 pt: between the parts of a row.
  package static let spacingS: CGFloat = 8
  /// 12 pt: between rows.
  package static let spacingM: CGFloat = 12
  /// 16 pt: inside a card.
  package static let spacingL: CGFloat = 16
  /// 24 pt: between sections.
  package static let spacingXL: CGFloat = 24
  /// Badges and fields.
  package static let radiusSmall: CGFloat = 4
  /// Cards.
  package static let radiusMedium: CGFloat = 8
  /// A measured value: digits of equal width, so a column of numbers lines up.
  package static let valueFont = Font.body.monospacedDigit()
  /// A value's unit and delta.
  package static let captionFont = Font.caption.monospacedDigit()
}
