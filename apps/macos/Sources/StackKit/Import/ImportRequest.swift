package import FilterKit

/// What the user chose on the Import sheet: the capture folders, the scan overrides and the
/// calibration choices — under the legacy `RunRequest` wire keys (`internal/job/manager.go`), Go's
/// `omitempty` included, so a stored request reads like a legacy job's params.
package struct ImportRequest: Equatable, Sendable {
  /// The capture folders; the first is the primary one (`path`).
  package var paths: [String]
  /// Filter → channel; `ignore` drops those lights (`filter_map`).
  package var filterMap: [String: String] = [:]
  /// Mono or colour stack (`color_model`); `auto` defers to the scan.
  package var colorModel = ColorChoice.auto
  /// Set ids the user dropped (`exclude_sets`).
  package var excludeSets: [String] = []
  /// Light set id → clip filter of a colour night (`filter_set_overrides`).
  package var filterSets: [String: FilterSet] = [:]
  /// Calibration suggestion ids the user unchecked (`calib_exclude`).
  package var calibExclude: [String] = []
  /// Applies the masters even when they do not match (`force_calibration_frames`).
  package var forceCalibration = false

  /// An import of `paths` with no override.
  package init(paths: [String]) {
    self.paths = paths
  }

  /// The overrides the scan honours; channel detection keeps its defaults.
  package var overrides: InspectOverrides {
    var overrides = InspectOverrides()
    overrides.filterMap = filterMap
    overrides.excludeSets = excludeSets
    overrides.filterSets = filterSets
    overrides.colorModel = colorModel
    return overrides
  }
}

// MARK: - Wire format

extension ImportRequest: Codable {
  private enum Key: String, CodingKey {
    case path, paths
    case filterMap = "filter_map"
    case colorModel = "color_model"
    case excludeSets = "exclude_sets"
    case filterSets = "filter_set_overrides"
    case calibExclude = "calib_exclude"
    case forceCalibration = "force_calibration_frames"
  }

  /// Decodes a legacy body: `paths` when present, else the single `path`; unknown values throw
  /// `InspectError`.
  package init(from decoder: any Decoder) throws {
    let wire = try decoder.container(keyedBy: Key.self)
    let paths = try wire.decodeIfPresent([String].self, forKey: .paths) ?? []
    let path = try wire.decodeIfPresent(String.self, forKey: .path)
    self.init(paths: paths.isEmpty ? path.map { [$0] } ?? [] : paths)
    filterMap = try wire.decodeIfPresent([String: String].self, forKey: .filterMap) ?? [:]
    colorModel = try ColorChoice(
      parsing: wire.decodeIfPresent(String.self, forKey: .colorModel) ?? "")
    excludeSets = try wire.decodeIfPresent([String].self, forKey: .excludeSets) ?? []
    filterSets = try (wire.decodeIfPresent([String: String].self, forKey: .filterSets) ?? [:])
      .mapValues(FilterSet.init(inspecting:))
    calibExclude = try wire.decodeIfPresent([String].self, forKey: .calibExclude) ?? []
    forceCalibration = try wire.decodeIfPresent(Bool.self, forKey: .forceCalibration) ?? false
  }

  /// Encodes only what is set, as Go's `omitempty` did; `paths` only for several folders.
  package func encode(to encoder: any Encoder) throws {
    var wire = encoder.container(keyedBy: Key.self)
    try wire.encodeIfPresent(paths.first, forKey: .path)
    if paths.count > 1 { try wire.encode(paths, forKey: .paths) }
    if !filterMap.isEmpty { try wire.encode(filterMap, forKey: .filterMap) }
    if colorModel != .auto { try wire.encode(colorModel.rawValue, forKey: .colorModel) }
    if !excludeSets.isEmpty { try wire.encode(excludeSets, forKey: .excludeSets) }
    if !filterSets.isEmpty {
      try wire.encode(filterSets.mapValues(\.rawValue), forKey: .filterSets)
    }
    if !calibExclude.isEmpty { try wire.encode(calibExclude, forKey: .calibExclude) }
    if forceCalibration { try wire.encode(true, forKey: .forceCalibration) }
  }
}
