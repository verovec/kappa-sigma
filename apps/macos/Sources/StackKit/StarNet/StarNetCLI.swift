package import Foundation
internal import Subprocess
internal import System

/// The two command lines StarNet has had (legacy `internal/starnet/runner.go`).
package enum StarNetCLI: Equatable, Sendable {
  /// StarNet++ v2: `starnet++ <in.tif> <out.tif> [stride]`.
  case positional
  /// StarNet2 v2.5+, which refuses positional arguments: `starnet2 -i <in> -o <out> [-s stride]`.
  case flags

  /// The schema prefix `--machine-info` reports on the flag generation.
  static let machineInfoSchema = "starnetastro.cli.machine-info"

  /// The arguments turning `input` into `output`; a stride is passed only when set.
  package func arguments(input: URL, output: URL, stride: Int? = nil) -> [String] {
    switch self {
    case .positional:
      [input.path, output.path] + (stride.map { [String($0)] } ?? [])
    case .flags:
      ["-i", input.path, "-o", output.path] + (stride.map { ["-s", String($0)] } ?? [])
    }
  }

  /// The generation of a `--machine-info` answer: JSON from its first `{` whose `schema` names
  /// the StarNet2 CLI; anything else (or a failed probe) is the positional generation.
  package static func generation(machineInfo output: String, exitedCleanly: Bool) -> Self {
    guard exitedCleanly, let brace = output.firstIndex(of: "{"),
      let json = try? JSONSerialization.jsonObject(with: Data(output[brace...].utf8)),
      let schema = (json as? [String: Any])?["schema"] as? String,
      schema.hasPrefix(machineInfoSchema)
    else { return .positional }
    return .flags
  }

  /// Asks the StarNet at `binary` which generation it is (`--machine-info`).
  package static func detect(binary: String) async -> Self {
    guard
      let result = try? await Subprocess.run(
        .path(FilePath(binary)), arguments: ["--machine-info"], input: .none,
        output: .string(limit: 1 << 16), error: .discarded)
    else { return .positional }
    let clean = if case .exited(0) = result.terminationStatus { true } else { false }
    return generation(machineInfo: result.standardOutput, exitedCleanly: clean)
  }
}
