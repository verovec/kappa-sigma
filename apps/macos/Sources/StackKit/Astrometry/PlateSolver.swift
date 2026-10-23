package import Foundation
package import ImageKit
internal import Synchronization
internal import os

/// Plate solving with Siril (card 0093): the image as is, the values the user confirmed, and
/// Siril's solution back as WCS cards — the pixels are never Siril's.
///
/// Siril runs on the app's own settings file (`-i`, in `support`): the user's Siril
/// configuration is never read or rewritten (a plain `platesolve` saves focal and pixel size as
/// new defaults), and the local catalogue paths are the app's, so a missing catalogue fails
/// instead of Siril silently going online (`docs/design/validation-e17.md`).
package struct PlateSolver: Sendable {
  /// What a solve gives back.
  package struct Solved: Sendable {
    /// What Siril reported.
    package let solution: PlateSolution
    /// The solution written by Siril.
    package let wcs: WCS
  }

  /// The runner (over `configFile`, for the live one).
  package let siril: SirilRunner
  /// The app's Siril settings file.
  package let configFile: URL
  /// The folder holding the local Gaia catalogue.
  package let catalogues: URL

  /// A solver over `siril`, its settings in `support`, the local catalogue in `catalogues`.
  package init(siril: SirilRunner, support: URL, catalogues: URL) {
    self.siril = siril
    configFile = support.appendingPathComponent("siril-platesolve.ini")
    self.catalogues = catalogues
  }

  /// The solver over the `siril-cli` at `binary`, run with `-i` on its own settings file.
  package static func live(binary: String, support: URL, catalogues: URL) -> Self {
    let file = support.appendingPathComponent("siril-platesolve.ini")
    return Self(
      siril: .live(binary: binary, initFile: file), support: support, catalogues: catalogues)
  }

  /// `~/Library/Application Support/AstroStack`: where the app keeps its tool settings.
  package static var supportFolder: URL {
    URL.applicationSupportDirectory.appendingPathComponent("AstroStack", isDirectory: true)
  }

  /// Solves `image` with `request`, working in a fresh folder under `scratch` (removed after).
  @concurrent
  package func solve(
    _ image: sending AstroImage, request: PlateSolveRequest, scratch: URL,
    onProgress: @escaping @Sendable (ToolProgress) -> Void
  ) async throws -> Solved {
    let astrometric = catalogues.appendingPathComponent(SirilAppSettings.astrometricFile)
    if request.catalogue == .localGaia,
      !FileManager.default.fileExists(atPath: astrometric.path)
    {
      throw PlateSolveError.catalogueMissing(path: astrometric.path)
    }
    try SirilAppSettings.write(to: configFile, catalogues: catalogues)
    let folder = scratch.appendingPathComponent("platesolve-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FITSFile.create(image, keeping: nil, at: folder.appendingPathComponent("input.fits"))
    let script = SirilScript([
      .load("input"), .platesolveForced(request.arguments), .save("solved"),
    ])
    let lines = Mutex<[String]>([])
    do {
      _ = try await siril.run(script, folder) { line in
        lines.withLock { $0.append(line.text) }
        onProgress(ToolProgress(line: line.text, percent: line.percent))
      }
    } catch let error as SirilError {
      // Stop tears Siril down: its exit is the cancellation, not a failed solve.
      try Task.checkCancellation()
      throw Self.failure(error, lines: lines.withLock { $0 })
    }
    try Task.checkCancellation()
    let log = lines.withLock { $0 }
    do {
      return try Self.solved(log: log, file: folder.appendingPathComponent("solved.fits"))
    } catch {
      // The folder is removed on return: Siril's whole log stays in the system log.
      Self.logger.error(
        "plate solve read nothing: \(log.joined(separator: "\n"), privacy: .public)")
      throw error
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/platesolve")

  /// The solution Siril's `log` reports and `file` carries, or which of the two is missing.
  package static func solved(log: [String], file: URL) throws -> Solved {
    guard let solution = PlateSolution(lines: log) else {
      let said = log.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      throw PlateSolveError.noReport(lastLines: said.suffix(3).joined(separator: " · "))
    }
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw PlateSolveError.noFile(path: file.path)
    }
    guard let wcs = (try? FITSFile.read(at: file)).flatMap({ WCS(header: $0.header) }) else {
      throw PlateSolveError.noSolution(path: file.path)
    }
    return Solved(solution: solution, wcs: wcs)
  }

  /// Siril's own reason: its `Plate solving failed: …` line, else the script's hint.
  private static func failure(_ error: SirilError, lines: [String]) -> Error {
    if let line = lines.last(where: { $0.hasPrefix("Plate solving failed") }) {
      return PlateSolveError.failed(reason: line)
    }
    if case .scriptFailed(_, let hint) = error, !hint.isEmpty {
      return PlateSolveError.failed(reason: hint)
    }
    return error
  }
}
