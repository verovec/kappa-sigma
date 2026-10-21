/// The bundle's statistics of a layer, given to a process as an input (R2: a process does not
/// measure the image itself).
package struct LayerStats: Equatable, Sendable {
  /// One entry per plane.
  package let channels: [ChannelStats]
  /// An emission layer's continuum scale k, fitted on the stack (`continuum_k`).
  package let continuumK: Double?
  /// The plane k was fitted against, as `LayerPlane` names it (`R`, `RGB.r`…: `continuum_ref`).
  package let continuumReference: String?

  /// Statistics of `channels`, with an emission layer's continuum fit.
  package init(
    channels: [ChannelStats], continuumK: Double? = nil, continuumReference: String? = nil
  ) {
    self.channels = channels
    self.continuumK = continuumK
    self.continuumReference = continuumReference
  }
}

/// Robust statistics of one plane.
package struct ChannelStats: Equatable, Sendable {
  /// Median.
  package let median: Double
  /// MAD × 1.4826.
  package let madn: Double
  /// Smallest value.
  package let minimum: Double
  /// Largest value.
  package let maximum: Double

  /// The statistics of a plane.
  package init(median: Double, madn: Double, minimum: Double, maximum: Double) {
    self.median = median
    self.madn = madn
    self.minimum = minimum
    self.maximum = maximum
  }
}

/// A layer of the stack bundle a process can need.
///
/// Roles, not filters: which filters make a
/// role is StackKit's canonical filter list.
package enum LayerRole: String, Codable, CaseIterable, Sendable {
  /// The colour (or mono) base layer.
  case color
  /// A luminance layer.
  case luminance
  /// An emission-line layer (Hα, OIII, SII).
  case emission
  /// The starless layer.
  case starless
  /// The stars-only layer.
  case stars
  /// A mask.
  case mask

  /// Why a process needing `requires` cannot run with only `present` (`nil`: it can).
  ///
  /// The panel shows the reason on the greyed process.
  package static func unavailableReason(
    requires: [Self], present: Set<Self>
  ) -> String? {
    let missing = requires.filter { !present.contains($0) }
    guard !missing.isEmpty else { return nil }
    return "needs " + missing.map { "a \($0.rawValue) layer" }.joined(separator: " and ")
  }
}
