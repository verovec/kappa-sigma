package import AppKit
package import SwiftUI

/// The semantic colours of the app: one name per role, a light and a dark value each.
///
/// AppKit resolves them with the view's appearance. No asset catalog: the CLT SwiftPM build has
/// no `actool`.
///
/// Text and status colours keep 4.5:1 (WCAG AA) on `surface`; `canvas` — the area around the
/// image — is neutral grey in both appearances and never follows the accent colour, so the eye
/// judges a background's neutrality against no tint (`DesignTokensTests`).
package enum DesignColor: CaseIterable, Sendable {
  /// Window and panel background.
  case surface
  /// Around the image in the viewer: R = G = B.
  case canvas
  /// Body text.
  case textPrimary
  /// Captions, units, secondary values.
  case textSecondary
  /// A verdict that needs nothing.
  case statusOK
  /// A verdict worth a look (a gap, a warning).
  case statusAttention
  /// A failure.
  case statusError
  /// A tool or a value that is not there.
  case statusUnavailable
  /// The region outline drawn over the image.
  case regionOutline
  /// Behind the histogram plot, dark in both appearances like the image.
  case plotBackground
  /// Histogram red channel.
  case plotRed
  /// Histogram green channel.
  case plotGreen
  /// Histogram blue channel.
  case plotBlue
  /// Histogram of a mono image.
  case plotLuminance

  /// The value in `appearance`.
  package func value(in appearance: DesignAppearance) -> SRGB {
    let (light, dark) = Self.table(self)
    return SRGB(hex: appearance == .dark ? dark : light)
  }

  /// A dynamic AppKit colour: AppKit picks the value of the drawing appearance.
  package var nsColor: NSColor {
    NSColor(name: nil) { appearance in
      value(in: DesignAppearance(appearance)).nsColor
    }
  }

  /// The SwiftUI colour.
  package var color: Color { Color(nsColor: nsColor) }

  /// The colour AppKit draws in `appearance`.
  package func resolved(in appearance: DesignAppearance) -> SRGB? {
    SRGB(nsColor, in: appearance)
  }

  /// The canvas's grey level for the display kernel (`DisplayUniforms.canvasGrey`).
  package static func canvasGrey(in appearance: DesignAppearance) -> Float {
    Float(canvas.value(in: appearance).red)
  }

  /// `0xRRGGBB` in light, then dark.
  private static func table(_ token: Self) -> (UInt32, UInt32) {
    switch token {
    case .surface: (0xECECEC, 0x323232)
    case .canvas: (0x6B6B6B, 0x262626)
    case .textPrimary: (0x1D1D1F, 0xF2F2F2)
    case .textSecondary: (0x5C5C60, 0xB4B4B8)
    case .statusOK: (0x1A6B2C, 0x5FD07A)
    case .statusAttention: (0x8A5300, 0xF2B33D)
    case .statusError: (0xB3261E, 0xFF7A70)
    case .statusUnavailable: (0x5F5F5F, 0xA8A8A8)
    case .regionOutline: (0xFFD60A, 0xFFD60A)
    case .plotBackground: (0x1A1A1A, 0x141414)
    case .plotRed: (0xFF453A, 0xFF453A)
    case .plotGreen: (0x32D74B, 0x32D74B)
    case .plotBlue: (0x0A84FF, 0x0A84FF)
    case .plotLuminance: (0xB0B0B0, 0xB0B0B0)
    }
  }
}
