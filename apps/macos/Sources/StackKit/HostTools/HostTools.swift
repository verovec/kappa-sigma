internal import Foundation

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
    /// Whether a folder (an `.app` bundle) is at the path.
    package var isDirectory: @Sendable (String) -> Bool
    /// Siril's version at the path, throwing `SirilError` when it is not a usable Siril.
    package var sirilVersion: @Sendable (String) async throws -> String

    /// A probe answering with these closures.
    package init(
      isExecutable: @escaping @Sendable (String) -> Bool,
      isDirectory: @escaping @Sendable (String) -> Bool,
      sirilVersion: @escaping @Sendable (String) async throws -> String
    ) {
      self.isExecutable = isExecutable
      self.isDirectory = isDirectory
      self.sirilVersion = sirilVersion
    }

    /// The file system and `siril-cli --version`.
    package static let system = Probe(
      isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
      isDirectory: { path in
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
          && isFolder.boolValue
      },
      sirilVersion: { try await SirilTool.verify($0) })
  }

  /// The standard install of GraXpert.
  package static let graxpertDefaultPath = "/Applications/GraXpert.app"
  /// The standard install of StarNet2.
  package static let starnetDefaultPath = "/usr/local/bin/starnet2"

  /// The client over `probe`: each tool at its environment override (`SIRIL_BIN`, `GRAXPERT_APP`,
  /// `STARNET_BIN`), else its standard install path.
  package static func live(
    environment: [String: String] = ProcessInfo.processInfo.environment, probe: Probe = .system
  ) -> HostTools {
    HostTools { tool in
      switch tool {
      case .siril:
        await siril(at: SirilTool.path(environment: environment), probe: probe)
      case .graxpert:
        found(
          override(environment, "GRAXPERT_APP") ?? graxpertDefaultPath, if: probe.isDirectory)
      case .starnet:
        found(override(environment, "STARNET_BIN") ?? starnetDefaultPath, if: probe.isExecutable)
      }
    }
  }

  private static func siril(at path: String, probe: Probe) async -> ToolStatus {
    guard probe.isExecutable(path) else { return .missing(path: path) }
    do {
      return .found(path: path, version: try await probe.sirilVersion(path))
    } catch SirilError.tooOld(let version) {
      return .tooOld(path: path, version: version)
    } catch {
      // Not Siril, or an unreadable version: nothing the app's scripts can drive.
      return .missing(path: path)
    }
  }

  private static func found(_ path: String, if exists: (String) -> Bool) -> ToolStatus {
    exists(path) ? .found(path: path, version: nil) : .missing(path: path)
  }

  private static func override(_ environment: [String: String], _ key: String) -> String? {
    environment[key].flatMap { $0.isEmpty ? nil : $0 }
  }
}
