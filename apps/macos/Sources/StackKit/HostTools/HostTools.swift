internal import Foundation
internal import OSLog

/// Finds the host tools: a client of one closure, so the app shows a fake status in tests and the
/// real one at launch (conventions « Dependencies are explicit »).
///
/// It only reports; nothing ever falls back to another tool or algorithm when one is missing (R2).
package struct HostTools: Sendable {
  /// The status of `tool`, probed now.
  package var locate: @Sendable (HostTool) async -> ToolStatus

  /// A client answering with `locate`.
  package init(locate: @escaping @Sendable (HostTool) async -> ToolStatus) {
    self.locate = locate
  }

  /// What the live client asks of the machine; tests substitute each answer.
  package struct Probe: Sendable {
    /// Whether an executable file is at the path.
    package var isExecutable: @Sendable (String) -> Bool
    /// Whether an app bundle whose executable can run is at the path.
    package var isApp: @Sendable (String) -> Bool
    /// Siril's version at the path, throwing `SirilError` when it is not a usable Siril.
    package var sirilVersion: @Sendable (String) async throws -> String

    /// A probe answering with these closures.
    package init(
      isExecutable: @escaping @Sendable (String) -> Bool,
      isApp: @escaping @Sendable (String) -> Bool,
      sirilVersion: @escaping @Sendable (String) async throws -> String
    ) {
      self.isExecutable = isExecutable
      self.isApp = isApp
      self.sirilVersion = sirilVersion
    }

    /// The file system and `siril-cli --version`.
    package static let system = Self(
      isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
      isApp: { path in
        guard let executable = Bundle(path: path)?.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
      },
      sirilVersion: { try await SirilTool.verify($0) })
  }

  /// The standard install of GraXpert.
  package static let graxpertDefaultPath = "/Applications/GraXpert.app"
  /// The standard install of StarNet2.
  package static let starnetDefaultPath = "/usr/local/bin/starnet2"

  /// How long `siril-cli --version` may take before Siril counts as unusable.
  package static let versionTimeout: Duration = .seconds(10)

  /// The client over `probe`: each tool at its environment override (`SIRIL_BIN`, `GRAXPERT_APP`,
  /// `STARNET_BIN`), else its standard install path; Siril's version probe gives up after
  /// `timeout`.
  package static func live(
    environment: [String: String] = ProcessInfo.processInfo.environment, probe: Probe = .system,
    timeout: Duration = versionTimeout
  ) -> Self {
    Self { tool in
      switch tool {
      case .siril:
        await siril(at: SirilTool.path(environment: environment), probe: probe, timeout: timeout)
      case .graxpert:
        found(
          override(environment, "GRAXPERT_APP") ?? graxpertDefaultPath, if: probe.isApp)
      case .starnet:
        found(override(environment, "STARNET_BIN") ?? starnetDefaultPath, if: probe.isExecutable)
      }
    }
  }

  private static func siril(at path: String, probe: Probe, timeout: Duration) async -> ToolStatus {
    guard probe.isExecutable(path) else { return .missing(path: path) }
    do {
      guard let version = try await version(of: path, probe: probe, timeout: timeout) else {
        logger.error("siril-cli --version at \(path, privacy: .public) gave no answer in time")
        return .missing(path: path)
      }
      return .found(path: path, version: version)
    } catch SirilError.tooOld(let version) {
      return .tooOld(path: path, version: version)
    } catch {
      // Not Siril, or an unreadable version: nothing the app's scripts can drive.
      logger.error("Siril at \(path, privacy: .public) is unusable: \(error, privacy: .public)")
      return .missing(path: path)
    }
  }

  /// The version `probe` reads, or `nil` when it takes longer than `timeout` (it is cancelled).
  private static func version(of path: String, probe: Probe, timeout: Duration) async throws
    -> String?
  {
    try await withThrowingTaskGroup(of: String?.self) { group in
      group.addTask { try await probe.sirilVersion(path) }
      group.addTask {
        try await Task.sleep(for: timeout)
        return nil
      }
      defer { group.cancelAll() }
      return try await group.next() ?? nil
    }
  }

  private static func found(_ path: String, if exists: (String) -> Bool) -> ToolStatus {
    exists(path) ? .found(path: path, version: nil) : .missing(path: path)
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/hosttools")

  /// `environment[key]`, an empty value counting as unset (shared with `SirilTool.path`).
  static func override(_ environment: [String: String], _ key: String) -> String? {
    environment[key].flatMap { $0.isEmpty ? nil : $0 }
  }
}
