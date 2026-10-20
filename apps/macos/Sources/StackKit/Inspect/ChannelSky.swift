/// A set's per-channel sky level, in ADU above the bias floor.
package struct ChannelSky: Equatable, Sendable {
  package var r: Double
  package var g: Double
  package var b: Double

  /// The three channels.
  package init(r: Double, g: Double, b: Double) {
    self.r = r
    self.g = g
    self.b = b
  }

  /// The scalar the rate thresholds are written against: the mean of the channels.
  package var amplitude: Double { (r + g + b) / 3 }

  /// The dual-band signature: Ha feeds red hardest and only OIII feeds blue, so R > G > B.
  package var isRedDominant: Bool { r > g && g > b }

  /// The broadband signature, the exact complement: red does not lead.
  package var isGreenBlueDominant: Bool { g >= r || b >= r }

  func scaled(_ factor: Double) -> Self { Self(r: r * factor, g: g * factor, b: b * factor) }
}
