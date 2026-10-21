package import AppKit

/// A colour as its sRGB components in 0…1: what a token resolves to, and what WCAG contrast is
/// computed from.
package struct SRGB: Equatable, Sendable, CustomStringConvertible {
  /// Red, 0…1.
  package var red: Double
  /// Green, 0…1.
  package var green: Double
  /// Blue, 0…1.
  package var blue: Double

  /// The colour from its three components.
  package init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// `0xRRGGBB`.
  package init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  /// `colour` as AppKit draws it in `appearance`; `nil` when it has no sRGB form (a pattern).
  package init?(_ colour: NSColor, in appearance: DesignAppearance) {
    var resolved: NSColor?
    appearance.nsAppearance.performAsCurrentDrawingAppearance {
      resolved = colour.usingColorSpace(.sRGB)
    }
    guard let resolved else { return nil }
    self.init(
      red: Double(resolved.redComponent), green: Double(resolved.greenComponent),
      blue: Double(resolved.blueComponent))
  }

  /// WCAG 2.x relative luminance.
  package var relativeLuminance: Double {
    func linear(_ value: Double) -> Double {
      value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG contrast ratio with `other`, 1…21, whichever is lighter.
  package func contrast(with other: Self) -> Double {
    let (mine, theirs) = (relativeLuminance, other.relativeLuminance)
    return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
  }

  /// The colour for AppKit.
  package var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
  }

  package var description: String {
    let hex = [red, green, blue].map { String(Int(($0 * 255).rounded()), radix: 16) }
    return "#" + hex.map { $0.count < 2 ? "0" + $0 : $0 }.joined()
  }
}
