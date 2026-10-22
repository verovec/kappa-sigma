internal import Foundation

/// What Siril reports of a solve (its log lines), shown in the panel.
package struct PlateSolution: Equatable, Sendable {
  /// Image centre, right ascension in degrees.
  package var centerRA: Double
  /// Image centre, declination in degrees.
  package var centerDec: Double
  /// Sampling, arcseconds per pixel.
  package var scaleArcsecPerPx: Double
  /// « Up is … deg CounterclockWise wrt. N ».
  package var rotationDeg: Double
  /// The focal length the solution implies, millimetres.
  package var focalMm: Double?
  /// The pixel size used, micrometres.
  package var pixelSizeUm: Double?
  /// Width × height as Siril prints it (`53' 11.66" x 39' 53.75"`).
  package var fieldOfView: String?
  /// The catalogue the stars came from.
  package var catalogue: String?
  /// How far the solved centre is from the one given, arcminutes.
  package var offsetArcmin: Double?

  /// The solution in `lines`, or `nil` when they lack a centre, a scale or a rotation.
  package init?(lines: [String]) {
    func value(_ pattern: String) -> String? {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      for line in lines {
        let whole = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, range: whole),
          let group = Range(match.range(at: 1), in: line)
        {
          return String(line[group]).trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    }
    guard let center = value(#"Image center: (alpha: .+)$"#),
      let scale = value(#"Resolution:\s+([0-9.]+) arcsec/px"#).flatMap(Double.init),
      let rotation = value(#"Up is ([+-]?[0-9.]+) deg"#).flatMap(Double.init),
      let (ra, dec) = Self.center(center)
    else { return nil }
    centerRA = ra
    centerDec = dec
    scaleArcsecPerPx = scale
    rotationDeg = rotation
    focalMm = value(#"Focal length:\s+([0-9.]+) mm"#).flatMap(Double.init)
    pixelSizeUm = value(#"Pixel size:\s+([0-9.]+) µm"#).flatMap(Double.init)
    fieldOfView = value(#"Field of view:\s+(.+)$"#)
    catalogue = value(#"Fetched \d+ stars from (.+) catalogue"#)
    offsetArcmin = value(#"Was ([0-9.]+) arcmin from initial value"#).flatMap(Double.init)
  }

  /// `alpha: 00 42 48.778, delta: +41 16 17.054` in degrees.
  private static func center(_ text: String) -> (Double, Double)? {
    let parts = text.components(separatedBy: ", delta:")
    guard parts.count == 2 else { return nil }
    let alpha = parts[0].replacingOccurrences(of: "alpha:", with: "")
      .trimmingCharacters(in: .whitespaces)
    guard let ra = TargetCoordinates.rightAscension(alpha),
      let dec = TargetCoordinates.declination(parts[1].trimmingCharacters(in: .whitespaces))
    else { return nil }
    return (ra, dec)
  }
}
