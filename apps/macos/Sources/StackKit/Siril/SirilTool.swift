internal import Foundation
internal import Subprocess
internal import System

/// Where `siril-cli` is: `SIRIL_BIN`, else the app bundle.
///
/// A missing tool is a typed error the app shows as an install card, never a fallback to another
/// algorithm (R2).
package enum SirilTool {
  /// The standard install location on macOS.
  package static let defaultPath = "/Applications/Siril.app/Contents/MacOS/siril-cli"

  /// The executable path, checked to exist.
  package static func locate(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> String {
    let path = path(environment: environment)
    try requireExecutable(path)
    return path
  }

  /// Where Siril is looked for: `SIRIL_BIN` when set, else the standard install.
  package static func path(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    HostTools.override(environment, "SIRIL_BIN") ?? defaultPath
  }

  /// The locale every `siril-cli` runs under, set over the app's environment.
  ///
  /// The log readers (plate solve, SPCC, error hints) match Siril's English sentences, and Siril
  /// otherwise speaks the Mac's language (card 0124). Siril's own `[core] lang` outranks it.
  package static let englishLocale = [
    "LANG": "en_US.UTF-8", "LANGUAGE": "en", "LC_ALL": "en_US.UTF-8",
    "LC_MESSAGES": "en_US.UTF-8",
  ]

  /// What every `siril-cli` launch is started with.
  static var processEnvironment: Environment {
    ToolProcess.environment(overriding: englishLocale)
  }

  /// Throws `notInstalled` unless `path` is an executable file.
  package static func requireExecutable(_ path: String) throws {
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw SirilError.notInstalled(path: path)
    }
  }

  /// Checks `binary` exists and is Siril ≥ 1.4 (`--version`); returns the version.
  package static func verify(_ binary: String) async throws -> String {
    try requireExecutable(binary)
    var options = PlatformOptions()
    // A cancelled probe (the host-tool timeout) stops siril-cli: SIGTERM, then SIGKILL.
    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
    let result = try await Subprocess.run(
      .path(FilePath(binary)), arguments: ["--version"],
      environment: processEnvironment, platformOptions: options,
      output: .string(limit: 64 * 1024), error: .combinedWithOutput)
    return try SirilVersion.parse(result.standardOutput)
  }
}
