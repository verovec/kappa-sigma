package import Foundation
package import ImageKit
internal import Synchronization

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
  /// Siril's whole output of the last solve, kept beside its settings once the scratch folder
  /// is gone.
  package var logFile: URL { configFile.deletingPathExtension().appendingPathExtension("log") }
  /// Siril's output of the last solve that failed: a retry that succeeds keeps it.
  package var failedLogFile: URL {
    configFile.deletingPathExtension().appendingPathExtension("failed.log")
  }

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
    var failed = true
    defer { keep(lines.withLock { $0 }, failed: failed) }
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
    let solved = try Self.solved(
      log: lines.withLock { $0 }, file: folder.appendingPathComponent("solved.fits"),
      kept: failedLogFile)
    failed = false
    return solved
  }

  /// Writes Siril's `lines` to `logFile`, and to `failedLogFile` when the solve `failed`: never
  /// a stopped solve's or an empty one, which would replace the log an earlier failure named.
  private func keep(_ lines: [String], failed: Bool) {
    guard !lines.isEmpty, !Task.isCancelled else { return }
    let data = Data(lines.joined(separator: "\n").utf8)
    try? data.write(to: logFile, options: .atomic)
    if failed { try? data.write(to: failedLogFile, options: .atomic) }
  }

  /// The solution Siril's `log` reports and `file` carries, or which part is missing; the
  /// errors name `kept`, where the log stays once the scratch folder is gone.
  package static func solved(log: [String], file: URL, kept: URL) throws -> Solved {
    guard let solution = PlateSolution(lines: log) else {
      // Siril saying it solved is a report this reader missed, not a solve that failed.
      if log.contains(where: { $0.contains("Siril solve succeeded") }) {
        throw PlateSolveError.reportUnread(log: kept.path)
      }
      throw PlateSolveError.noReport(lastLines: platesolveTail(log), log: kept.path)
    }
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw PlateSolveError.noFile(log: kept.path)
    }
    guard let header = try? FITSFile.read(at: file).header else {
      throw PlateSolveError.unreadableFile(log: kept.path)
    }
    guard let wcs = WCS(header: header) else { throw PlateSolveError.noSolution(log: kept.path) }
    return Solved(solution: solution, wcs: wcs)
  }

  /// The last three lines `platesolve` printed (the whole log's when it never ran), « — » when
  /// there are none: never the script's closing lines, command echoes or progress, which say
  /// nothing of the solve.
  package static func platesolveTail(_ log: [String]) -> String {
    let said = log.map { $0.trimmingCharacters(in: .whitespaces) }
    let echo = SirilOutput.isCommandEcho
    let start = said.lastIndex { echo($0) && $0.hasSuffix("platesolve") }
    let end = start.flatMap { first in said[(first + 1)...].firstIndex(where: echo) }
    let solve = start.map { said[($0 + 1)..<(end ?? said.endIndex)] } ?? said[...]
    let closing = ["Script execution", "Total execution time", "closing pipes"]
    let words = solve.filter { line in
      !line.isEmpty && !SirilOutput.isNoise(line) && !closing.contains { line.hasPrefix($0) }
    }.suffix(3)
    return words.isEmpty ? "—" : words.joined(separator: " · ")
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
