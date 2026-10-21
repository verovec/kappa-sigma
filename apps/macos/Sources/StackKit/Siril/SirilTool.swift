internal import Darwin
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
    let path = environment["SIRIL_BIN"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultPath
    try requireExecutable(path)
    return path
  }

  /// Throws `notInstalled` unless `path` is an executable file.
  package static func requireExecutable(_ path: String) throws {
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw SirilError.notInstalled(path: path)
    }
  }

  /// How every `siril-cli` is launched: in its own process group, stopped as a group (SIGTERM,
  /// then SIGKILL two seconds later) when the task is cancelled.
  ///
  /// Siril 1.4 starts Python checks at every launch. A Python orphaned between its launcher and
  /// the bundle's `Python.app` breaks that binary's parent launch constraint: macOS kills it with
  /// a crash dialog, and Siril then deletes its venv (siril#1957). Its children share its group.
  static var platformOptions: PlatformOptions {
    var options = PlatformOptions()
    options.processGroupID = 0
    options.teardownSequence = [
      .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2))
    ]
    return options
  }

  /// Kills what is left in Siril's process group once Siril has exited, on its own or not (the
  /// teardown only runs on cancellation, and Siril also exits at a script's end or a pipe's EOF).
  ///
  /// A group id is not reused while one of its members lives, so a group that still lists a
  /// member is Siril's: the kill cannot reach another process.
  static func killLeftovers(ofGroup group: pid_t) {
    var member: pid_t = 0
    let bytes = proc_listpids(
      UInt32(PROC_PGRP_ONLY), UInt32(group), &member, Int32(MemoryLayout<pid_t>.size))
    guard bytes > 0 else { return }
    killpg(group, SIGKILL)
  }

  /// Checks `binary` exists and is Siril ≥ 1.4 (`--version`); returns the version.
  package static func verify(_ binary: String) async throws -> String {
    try requireExecutable(binary)
    let result = try await Subprocess.run(
      .path(FilePath(binary)), arguments: ["--version"], platformOptions: platformOptions,
      output: .string(limit: 64 * 1024), error: .combinedWithOutput)
    return try SirilVersion.parse(result.standardOutput)
  }
}
