package import Foundation

/// The OpenNGC overlay (legacy `openngc.go`): types, ellipses, surface brightness, morphology and
/// common names matched by name onto Siril's objects, never their coordinates.
extension SkyCatalogue {
  /// One overlay row.
  package struct OverlayEntry: Equatable, Sendable {
    /// The type code (`G`, `HII`, `SNR`…).
    package var type: String
    package var majorAxisArcmin: Double?
    package var minorAxisArcmin: Double?
    package var positionAngleDeg: Double?
    package var surfaceBrightness: Double?
    /// Hubble morphology, nil when blank.
    package var morphology: String?
    package var commonNames: [String]
  }

  /// The committed slimmed OpenNGC (CC-BY-SA-4.0, `Resources/Catalogue/README.md`).
  package static var openNGCOverlay: URL? {
    StackKitResources.bundle.url(
      forResource: "openngc", withExtension: "csv", subdirectory: "Catalogue")
  }

  /// The overlay rows of `url` by normalised name; a row without a name or a type is skipped.
  package static func overlayEntries(contentsOf url: URL) throws -> [String: OverlayEntry] {
    let (columns, rows) = table(try read(url))
    var entries: [String: OverlayEntry] = [:]
    for row in rows {
      let cell = { (name: String) in columns[name].flatMap { $0 < row.count ? row[$0] : nil } ?? ""
      }
      let key = normalize(cell("name"))
      guard !key.isEmpty, !cell("type").isEmpty else { continue }
      entries[key] = OverlayEntry(
        type: cell("type"), majorAxisArcmin: number(cell("majax")),
        minorAxisArcmin: number(cell("minax")), positionAngleDeg: number(cell("posang")),
        surfaceBrightness: number(cell("surfbr")),
        morphology: cell("hubble").isEmpty ? nil : cell("hubble"),
        commonNames: cell("common").split(separator: "/").map {
          $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
    }
    return entries
  }

  /// Every object enriched by the entry of its first key the overlay holds (its primary NGC/IC
  /// name, or a Messier object's NGC alias); OpenNGC's major axis replaces Siril's diameter.
  func overlaid(with entries: [String: OverlayEntry]) -> Self {
    guard !entries.isEmpty else { return self }
    return mapping { object in
      guard let entry = object.keys.lazy.compactMap({ entries[$0] }).first else { return object }
      var enriched = object
      enriched.type = entry.type
      enriched.morphology = entry.morphology
      enriched.commonNames = entry.commonNames
      enriched.majorAxisArcmin = entry.majorAxisArcmin ?? object.majorAxisArcmin
      enriched.minorAxisArcmin = entry.minorAxisArcmin
      enriched.positionAngleDeg = entry.positionAngleDeg
      enriched.surfaceBrightness = entry.surfaceBrightness
      return enriched
    }
  }
}
