package import Foundation
package import ImageKit
internal import Synchronization

/// Colour calibration with Siril (card 0094): SPCC or PCC on a plate-solved image, exactly as
/// the user chose — never one after the other, never a neutralisation instead (R2).
///
/// SPCC names are checked against Siril's own lists first (`spcc_list`): Siril 1.4.4 runs an
/// unknown sensor name as the previous one. Siril runs on the app's settings file
/// (`SirilAppSettings`, `-i`), so the user's last SPCC choices are neither read nor changed.
package struct ColourCalibrator: Sendable {
  /// What a calibration gives back.
  package struct Calibrated {
    /// Siril's calibrated pixels, with the input's metadata (its solution kept).
    package let image: AstroImage
    /// What Siril applied.
    package let report: ColourCalibrationReport
  }

  /// The runner (over `configFile`, for the live one).
  package let siril: SirilRunner
  /// The app's Siril settings file.
  package let configFile: URL
  /// The folder holding the local Gaia catalogues.
  package let catalogues: URL

  /// A calibrator over `siril`, its settings in `support`, the local catalogues in `catalogues`.
  package init(siril: SirilRunner, support: URL, catalogues: URL) {
    self.siril = siril
    configFile = support.appendingPathComponent(Self.settingsName)
    self.catalogues = catalogues
  }

  /// The calibrator over the `siril-cli` at `binary`, run with `-i` on its own settings file.
  package static func live(binary: String, support: URL, catalogues: URL) -> Self {
    let file = support.appendingPathComponent(settingsName)
    return Self(
      siril: .live(binary: binary, initFile: file), support: support, catalogues: catalogues)
  }

  private static let settingsName = "siril-colour.ini"
  /// The Gaia DR3 xp_sampled files SPCC reads, by prefix.
  private static let spectraPrefix = "siril_cat1_healpix8_xpsamp_"
  /// `spcc_list` headings, by the kind each lists.
  private static let headings = [
    "OSC Sensors": "oscsensor", "OSC Filters": "oscfilter", "White References": "whiteref",
    "OSC Low-Pass Filters": "osclpf",
  ]

  /// Calibrates `image` with `request`, working in a fresh folder under `scratch` (removed after).
  @concurrent
  package func calibrate(
    _ image: sending AstroImage, request: ColourCalibrationRequest, scratch: URL,
    onProgress: @escaping @Sendable (ToolProgress) -> Void
  ) async throws -> sending Calibrated {
    guard let wcs = image.metadata.wcs else { throw ColourCalibrationError.unsolved }
    try checkCatalogue(request)
    let folder = scratch.appendingPathComponent("colour-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    if case .spcc(let sensor, let filter, let reference) = request.method {
      try SirilAppSettings.write(to: configFile, catalogues: catalogues)
      try await checkNames(
        [.sensor: sensor, .filter: filter, .whiteReference: reference], in: folder)
    }
    // Siril reads the solution from the file it loads.
    try FITSFile.create(
      image, keeping: FITSHeader(cards: []).carrying(wcs),
      at: folder.appendingPathComponent("input.fits"))
    // Written last: a `spcc_list` run saves Siril's whole configuration back into the file.
    try SirilAppSettings.write(to: configFile, catalogues: catalogues)
    let lines = Mutex<[String]>([])
    do {
      _ = try await siril.run(
        SirilScript([.load("input"), request.command, .save("calibrated")]), folder
      ) { line in
        lines.withLock { $0.append(line.text) }
        onProgress(ToolProgress(line: line.text, percent: line.percent))
      }
    } catch let SirilError.scriptFailed(code, hint) {
      try Task.checkCancellation()
      throw ColourCalibrationError.failed(reason: hint.isEmpty ? "siril-cli exit \(code)" : hint)
    }
    try Task.checkCancellation()
    let output = folder.appendingPathComponent("calibrated.fits")
    guard FileManager.default.fileExists(atPath: output.path) else {
      throw ColourCalibrationError.noOutput(path: output.path)
    }
    guard let report = ColourCalibrationReport(lines: lines.withLock { $0 }) else {
      throw ColourCalibrationError.noFactors
    }
    return Calibrated(
      image: try BackgroundCache.read(output, metadata: image.metadata), report: report)
  }

  /// The names Siril lists, by kind, from the lines of `spcc_list` commands.
  package static func lists(_ lines: [String]) -> [String: [String]] {
    var lists: [String: [String]] = [:]
    var kind: String?
    for line in lines {
      if let heading = headings[line] {
        kind = heading
        lists[heading] = []
      } else if SirilOutput.isCommandEcho(line) || line.hasPrefix("Setting CWD") {
        kind = nil
      } else if let kind {
        lists[kind, default: []].append(line)
      }
    }
    return lists
  }

  private func checkNames(
    _ names: [ColourCalibrationError.NameKind: String], in folder: URL
  ) async throws {
    let lines = Mutex<[String]>([])
    let kinds = ColourCalibrationError.NameKind.allCases.filter { names[$0] != nil }
    let script = SirilScript(kinds.map { SirilCommand.spccList($0.rawValue) })
    _ = try await siril.run(script, folder) { line in lines.withLock { $0.append(line.text) } }
    let lists = Self.lists(lines.withLock { $0 })
    for kind in kinds {
      let name = names[kind] ?? ""
      guard lists[kind.rawValue]?.contains(name) == true else {
        throw ColourCalibrationError.unknownName(kind: kind, name: name)
      }
    }
  }

  private func checkCatalogue(_ request: ColourCalibrationRequest) throws {
    guard request.catalogue == .localGaia else { return }
    if case .spcc = request.method {
      let files = (try? FileManager.default.contentsOfDirectory(atPath: catalogues.path)) ?? []
      guard files.contains(where: { $0.hasPrefix(Self.spectraPrefix) }) else {
        throw ColourCalibrationError.catalogueMissing(path: catalogues.path)
      }
    } else {
      let file = catalogues.appendingPathComponent(SirilAppSettings.astrometricFile)
      guard FileManager.default.fileExists(atPath: file.path) else {
        throw ColourCalibrationError.catalogueMissing(path: file.path)
      }
    }
  }
}
