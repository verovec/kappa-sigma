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
  ///
  /// A probe that fails is the positional generation (legacy rule). One that does not answer
  /// within `timeout` is stopped and throws `StarNetError.probeTimedOut`: guessing would run a
  /// flag-only StarNet2 with positional arguments.
  package static func detect(binary: String, timeout: Duration = .seconds(60)) async throws
    -> Self
  {
    let answer = await withTaskGroup(of: Self?.self) { group in
      group.addTask { await probe(binary) }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
    guard let answer else { throw StarNetError.probeTimedOut(path: binary) }
    return answer
  }

  private static func probe(_ binary: String) async -> Self {
    var options = PlatformOptions()
    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
    guard
      let result = try? await Subprocess.run(
        .path(FilePath(binary)), arguments: ["--machine-info"], platformOptions: options,
        input: .none, output: .string(limit: 1 << 16), error: .discarded)
    else { return .positional }
    let clean = if case .exited(0) = result.terminationStatus { true } else { false }
    return generation(machineInfo: result.standardOutput, exitedCleanly: clean)
  }
}
