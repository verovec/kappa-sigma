/// CPU references of the colour processes (card 0053), in Float like the legacy tools.
///
/// Saturation is astrocomp's HSL block (`-sat`, `-sat-masked`) with the mask of
/// `gimp.saturationMaskLUT(0.12, 0.45, 0.70, 0.30)`, the star-core desaturation of
/// `gimp.starDesatMaskLUT(0.50, 0.85)` and the `desat` tool's Rec. 709 luma blend.
enum ColourOracle {
  /// `saturationMaskLUT` sampled at `x`: 0 to `low`, a ramp to `high`, 1 to `rolloff`, then down
  /// to `floor` at white.
  static func saturationMask(
    _ x: Float, low: Float = 0.12, high: Float = 0.45, rolloff: Float = 0.70, floor: Float = 0.30
  ) -> Float {
    let value: Float =
      if x <= low { 0 } else if x < high { (x - low) / (high - low) } else if x <= rolloff {
        1
      } else {
        1 - (x - rolloff) / (1 - rolloff) * (1 - floor)
      }
    return min(max(value, 0), 1)
  }

  /// `starDesatMaskLUT` sampled at `x`: 0 to `low`, a ramp to 1 at `high`.
  static func starMask(_ x: Float, low: Float = 0.50, high: Float = 0.85) -> Float {
    let value: Float = x <= low ? 0 : (x < high ? (x - low) / (high - low) : 1)
    return min(max(value, 0), 1)
  }

  /// One pixel through the saturation process.
  static func saturate(
    _ rgb: [Float], amount: Float, masked: Bool, starDesat: Float, lumaK: Float,
    mask: (Float) -> Float = { saturationMask($0) }
  ) -> [Float] {
    var (r, g, b) = (rgb[0], rgb[1], rgb[2])
    if amount != 0 || starDesat != 0 {
      let (mx, mn) = (max(r, g, b), min(r, g, b))
      let lightness = (mx + mn) / 2
      if mx != mn {
        var sat = lightness <= 0.5 ? (mx - mn) / (mx + mn) : (mx - mn) / (2 - mx - mn)
        let hue = Self.hue(r, g, b, mx: mx, mn: mn)
        sat *= 1 + amount * (masked ? mask(lightness) : 1)
        sat = min(sat, 1)
        sat *= 1 - starDesat * starMask(lightness)
        (r, g, b) = hslToRGB(hue, sat, lightness)
      }
    }
    if lumaK != 1 {
      let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
      (r, g, b) = (
        min(max(luma + (r - luma) * lumaK, 0), 1), min(max(luma + (g - luma) * lumaK, 0), 1),
        min(max(luma + (b - luma) * lumaK, 0), 1)
      )
    }
    return [r, g, b]
  }

  /// astrocomp's `hueOf`, in turns.
  static func hue(_ r: Float, _ g: Float, _ b: Float, mx: Float, mn: Float) -> Float {
    let delta = mx - mn
    var hue: Float
    if mx == r {
      hue = (g - b) / delta
      if hue < 0 { hue += 6 }
    } else if mx == g {
      hue = (b - r) / delta + 2
    } else {
      hue = (r - g) / delta + 4
    }
    return hue / 6
  }

  /// astrocomp's `hslToRGB`.
  static func hslToRGB(_ hue: Float, _ sat: Float, _ light: Float) -> (Float, Float, Float) {
    if sat == 0 { return (light, light, light) }
    let upper = light < 0.5 ? light * (1 + sat) : light + sat - light * sat
    let lower = 2 * light - upper
    func channel(_ turn: Float) -> Float {
      var turn = turn
      if turn < 0 { turn += 1 }
      if turn > 1 { turn -= 1 }
      if turn < 1.0 / 6 { return lower + (upper - lower) * 6 * turn }
      if turn < 1.0 / 2 { return upper }
      if turn < 2.0 / 3 { return lower + (upper - lower) * (2.0 / 3 - turn) * 6 }
      return lower
    }
    return (channel(hue + 1.0 / 3), channel(hue), channel(hue - 1.0 / 3))
  }
}
