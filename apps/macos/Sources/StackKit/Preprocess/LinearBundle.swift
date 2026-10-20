/// The linear bundle (`bundle.json`): a run's float layers on one grid with measured stats and
/// their provenance, what the Studio opens.
///
/// Schema `{version, run_id, color_model, grid, layers[{id, role, file, source, stats{bg, madn,
/// sky, snr}, continuum_k?}]}`; 0043 builds the same type from a legacy run.
package struct LinearBundle: Codable, Equatable, Sendable {
  /// What a layer is to the Studio.
  package enum Role: String, CaseIterable, Codable, Sendable {
    case rgb, line, lum, red, green, blue

    /// The role of a channel's filter: L/R/G/B by name, one-shot colour `rgb`, anything else a
    /// line (emission) layer.
    package init(filter: String) {
      switch Filter.token(filter) {
      case .luminance: self = .lum
      case .red: self = .red
      case .green: self = .green
      case .blue: self = .blue
      default: self = Filter.isColor(filter) ? .rgb : .line
      }
    }
  }

  /// The pixel grid every layer shares.
  package struct Grid: Codable, Equatable, Sendable {
    package var width: Int
    package var height: Int
  }

  /// Full-resolution statistics of a layer (physical values, planes averaged).
  package struct Stats: Codable, Equatable, Sendable {
    /// The median.
    package var bg: Double
    /// 1.4826 × the median absolute deviation from `bg`: the noise in σ units.
    package var madn: Double
    /// The median of the pixels at most 3 MADN above `bg`: the level without stars and objects.
    package var sky: Double
    /// `bg / madn`.
    package var snr: Double
  }

  /// One layer.
  package struct Layer: Codable, Equatable, Sendable {
    /// The channel (filter) it comes from.
    package var id: String
    package var role: Role
    /// The FITS file, relative to the bundle.
    package var file: String
    /// The stage that wrote it: `trim`, `aligned` or `master`.
    package var source: String
    package var stats: Stats
    /// The continuum scale of a line layer (multi-night Hα continuum subtraction, 0066).
    package var continuumK: Double?

    enum CodingKeys: String, CodingKey {
      case id, role, file, source, stats
      case continuumK = "continuum_k"
    }
  }

  static let currentVersion = 1

  package var version = Self.currentVersion
  package var runID: String
  package var colorModel: ColorModel
  package var grid: Grid
  package var layers: [Layer]

  enum CodingKeys: String, CodingKey {
    case version, grid, layers
    case runID = "run_id"
    case colorModel = "color_model"
  }
}
