internal import Foundation

/// What an export writes.
///
/// Which deliverables, in which formats, cropped and oriented how, named how. Every value is the
/// panel's; the defaults are the legacy deliverable set.
package struct ExportSettings: Codable, Equatable, Sendable {
  /// One file of the deliverable set.
  package enum Deliverable: String, CaseIterable, Codable, Sendable {
    /// The finished image: stars back at full presence, with the chosen star colour.
    case final = "final"
    /// StarNet's starless image.
    case starless = "final-starless"
    /// Stars at 75 % presence.
    case stars75 = "final-75-stars"
    /// Stars at 50 % presence.
    case stars50 = "final-50-stars"
    /// Stars at 25 % presence.
    case stars25 = "final-25-stars"

    /// The star presence it is rendered at (`nil`: the starless itself).
    package var presence: Double? {
      switch self {
      case .final: 1
      case .starless: nil
      case .stars75: 0.75
      case .stars50: 0.5
      case .stars25: 0.25
      }
    }
  }

  /// A file format.
  package enum Format: String, CaseIterable, Codable, Sendable {
    /// 16-bit PNG.
    case png16
    /// 16-bit TIFF.
    case tiff16
    /// 32-bit float FITS.
    case fits32

    /// The file name extension.
    package var fileExtension: String {
      switch self {
      case .png16: "png"
      case .tiff16: "tif"
      case .fits32: "fits"
      }
    }
  }

  /// A mirror applied at export (multi-night stacks come out mirrored: memory
  /// `multinight-parity-flip`), natively rather than through ffmpeg.
  package enum Orientation: String, CaseIterable, Codable, Sendable {
    /// As is.
    case none
    /// Left ↔ right.
    case hflip
    /// Top ↔ bottom.
    case vflip
  }

  /// The files of the set to write.
  package var deliverables: [Deliverable] = Deliverable.allCases
  /// The formats each one is written in.
  package var formats: [Format] = [.png16]
  /// Trimmed from each edge, as a fraction of the width and height (astrocomp `-crop`).
  package var cropFraction = 0.0
  /// The mirror.
  package var orientation = Orientation.none
  /// The file name, `{name}` standing for the deliverable's legacy name.
  package var nameTemplate = "{name}"
  /// The star colour of every starred deliverable (`StarRecompositionProcess` chroma; stardesat k).
  package var starColour = 0.25

  /// The legacy set: five PNGs, star colour 0.25, no crop or mirror.
  package init() {}

  /// `deliverable` written (`on`) or not, the set kept in its legacy order.
  package mutating func choose(_ deliverable: Deliverable, _ on: Bool) {
    deliverables = Deliverable.allCases.filter {
      $0 == deliverable ? on : deliverables.contains($0)
    }
  }

  /// `format` written (`on`) or not, the formats kept in their order.
  package mutating func choose(_ format: Format, _ on: Bool) {
    formats = Format.allCases.filter { $0 == format ? on : formats.contains($0) }
  }

  /// The file name of `deliverable` in `format`.
  package func fileName(_ deliverable: Deliverable, _ format: Format) -> String {
    nameTemplate.replacingOccurrences(of: "{name}", with: deliverable.rawValue) + "."
      + format.fileExtension
  }
}
