/// One deep-sky object of the catalogue (card 0129): its primary designation and every other name,
/// where it is (J2000, degrees) and what the lists and the OpenNGC overlay know of it.
///
/// Optional values are unknown, never 0: Siril's lists leave sizes and magnitudes empty for whole
/// catalogues (Sh2, LDN) and scattered NGC/IC rows.
package struct SkyObject: Equatable, Sendable {
  /// The list an object comes from, in load order: the first list wins the primary name.
  package enum Source: String, CaseIterable, Sendable {
    case messier, ngc, ic, sh2, ldn

    /// Siril's file of this list.
    package var file: String { rawValue + ".csv" }
  }

  /// The primary designation (`M31`, `NGC7000`, `Sh2-132`).
  package var name: String
  /// Right ascension, J2000, degrees.
  package var raDeg: Double
  /// Declination, J2000, degrees.
  package var decDeg: Double
  /// The list the primary designation comes from.
  package var source: Source
  /// Visual magnitude.
  package var magnitude: Double?
  /// Major axis (Siril's diameter, or OpenNGC's major axis), arcmin.
  package var majorAxisArcmin: Double?
  /// Minor axis (OpenNGC), arcmin.
  package var minorAxisArcmin: Double?
  /// Position angle of the major axis (OpenNGC), degrees.
  package var positionAngleDeg: Double?
  /// Surface brightness (OpenNGC), mag/arcsec².
  package var surfaceBrightness: Double?
  /// Hubble morphology (OpenNGC: `Sb`, `SABc`).
  package var morphology: String?
  /// OpenNGC's type code (`G`, `OCl`, `GCl`, `PN`, `HII`, `SNR`, …); the app words it.
  package var type: String?
  /// Every other designation and the lists' own friendly names (`NGC224`, `Andromeda galaxy`).
  package var aliases: [String]
  /// OpenNGC's common names (`Andromeda Galaxy`).
  package var commonNames: [String]

  /// An object of `source` at (`raDeg`, `decDeg`).
  package init(
    name: String, raDeg: Double, decDeg: Double, source: Source, magnitude: Double? = nil,
    majorAxisArcmin: Double? = nil, aliases: [String] = [], commonNames: [String] = []
  ) {
    self.name = name
    self.raDeg = raDeg
    self.decDeg = decDeg
    self.source = source
    self.magnitude = magnitude
    self.majorAxisArcmin = majorAxisArcmin
    self.aliases = aliases
    self.commonNames = commonNames
  }

  /// The keys the object answers to: its name and every alias, normalised (`SkyCatalogue.normalize`).
  var keys: [String] {
    ([name] + aliases).map(SkyCatalogue.normalize).filter { !$0.isEmpty }
  }

  /// `src` folded in (legacy `mergeInto`): missing photometry filled, its name and aliases absorbed.
  mutating func absorb(_ src: Self) {
    magnitude = magnitude ?? src.magnitude
    majorAxisArcmin = majorAxisArcmin ?? src.majorAxisArcmin
    for alias in [src.name] + src.aliases { addAlias(alias) }
  }

  /// Adds `candidate` unless it is blank, the primary name or an alias already (legacy `appendAlias`).
  mutating func addAlias(_ candidate: String) {
    let alias = candidate.trimmingCharacters(in: .whitespaces)
    let key = SkyCatalogue.normalize(alias)
    guard !key.isEmpty, key != SkyCatalogue.normalize(name),
      !aliases.contains(where: { SkyCatalogue.normalize($0) == key })
    else { return }
    aliases.append(alias)
  }
}
