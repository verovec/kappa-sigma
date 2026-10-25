/// An emission line the screens process can lay over the colour base, with its panel defaults.
package enum EmissionLine: String, CaseIterable, Sendable {
  /// Hα, 656 nm.
  case hydrogenAlpha = "Ha"
  /// [OIII], 501 nm.
  case oxygenIII = "OIII"
  /// [SII], 672 nm.
  case sulfurII = "SII"

  /// The bundle layer it reads.
  package var layerID: String { rawValue }

  /// The prefix of its parameter ids (`haBlack`, `oiiiOpacity`…).
  package var prefix: String { rawValue.lowercased() }

  /// How panels write it.
  package var name: String {
    switch self {
    case .hydrogenAlpha: "Hα"
    case .oxygenIII: "[OIII]"
    case .sulfurII: "[SII]"
    }
  }

  /// The id of its parameter `name` (`Enabled`, `Black`…).
  package func id(_ name: String) -> String { prefix + name }

  /// The continuum scale the bundle fitted on this line's layer and the plane it was fitted
  /// against (`continuum_k`, `continuum_ref`); `nil` without both: a scale without its plane
  /// cannot be applied.
  package func continuumFit(in layerStats: [String: LayerStats]) -> (k: Double, reference: String)?
  {
    guard let stats = layerStats[layerID], let k = stats.continuumK,
      let reference = stats.continuumReference
    else { return nil }
    return (k, reference)
  }

  /// On by default: the HOO-over-broadband layers; [SII] waits for the user.
  var enabledByDefault: Bool { self != .sulfurII }

  /// astrocomp's default opacities (`-ha-screen 0.85`, `-oiii-screen 0.78`).
  var defaultOpacity: Double {
    switch self {
    case .hydrogenAlpha: 0.85
    case .oxygenIII: 0.78
    case .sulfurII: 0.6
    }
  }

  /// Hα red, [OIII] teal (astrocomp), [SII] gold.
  var defaultTint: ScreenTint {
    switch self {
    case .hydrogenAlpha: .red
    case .oxygenIII: .teal
    case .sulfurII: .gold
    }
  }
}
