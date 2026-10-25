package import Foundation
package import ImageKit

/// What is under the cursor: the pixel, its linear value in every plane (the data, never the
/// stretched display), and RA/Dec when the header carries a TAN solution.
package struct PixelReadout: Equatable, Sendable {
  /// Column.
  package let x: Int
  /// Row, in file order.
  package let y: Int
  /// One linear value per plane.
  package let values: [Float]
  /// RA, Dec in degrees; `nil` without a plate solution.
  package let sky: Sky?

  /// RA, Dec in degrees.
  package struct Sky: Equatable, Sendable {
    /// Right ascension, [0, 360).
    package let ra: Double
    /// Declination.
    package let dec: Double

    /// RA, Dec in degrees.
    package init(ra: Double, dec: Double) {
      self.ra = ra
      self.dec = dec
    }

    /// `hh`h`mm`m`ss.s`s, wrapped at 24 h.
    package var raText: String {
      let tenths = Int((ra / 15 * 36_000).rounded()) % 864_000
      let (hours, minutes) = (tenths / 36_000, tenths / 600 % 60)
      let seconds = tenths % 600
      return "\(Self.two(hours))h\(Self.two(minutes))m\(Self.two(seconds / 10)).\(seconds % 10)s"
    }

    /// `±dd°mm′ss″`; the sign is kept for a negative Dec that rounds to zero.
    package var decText: String {
      let total = Int((abs(dec) * 3600).rounded())
      let sign = dec < 0 ? "−" : "+"
      return
        "\(sign)\(Self.two(total / 3600))°\(Self.two(total / 60 % 60))′\(Self.two(total % 60))″"
    }

    private static func two(_ value: Int) -> String {
      value < 10 ? "0\(value)" : "\(value)"
    }
  }

  /// The readout on one line in `locale`, as the View panel words it: `120, 48 · R 0,012345 G …
  /// · AD 00h42m44,3s Déc +41°16′09″` (the focus HUD, card 0127).
  package func summary(locale: Locale) -> String {
    let channels = values.indices.map { channel in
      ViewerPanel.channelName(channel, of: values.count) + " "
        + ViewerPanel.number(Double(values[channel]), digits: 6, locale: locale)
    }
    var parts = ["\(x), \(y)", channels.joined(separator: " ")]
    if let sky {
      let (ra, dec) = (
        String(localized: .renderKit("RA", locale: locale)),
        String(localized: .renderKit("Dec", locale: locale))
      )
      parts.append(
        ra + " " + LocaleNumber.decimalMark(sky.raText, locale: locale) + " " + dec + " "
          + sky.decText)
    }
    return parts.joined(separator: " · ")
  }

  /// The readout at (`x`, `y`), or `nil` outside the image.
  package init?(image: AstroImage, x: Int, y: Int) {
    guard (0..<image.width).contains(x), (0..<image.height).contains(y) else { return nil }
    self.x = x
    self.y = y
    values = image.planes.map { $0[y * image.width + x] }
    sky = image.metadata.wcs.map { wcs in
      let position = wcs.sky(x: Double(x), y: Double(y))
      return Sky(ra: position.ra, dec: position.dec)
    }
  }
}
