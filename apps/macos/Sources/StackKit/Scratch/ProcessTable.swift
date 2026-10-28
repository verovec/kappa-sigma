internal import Darwin
internal import Foundation
internal import ProjectKit

/// What the sweep may ask of the system's processes.
///
/// Who runs under a pid, which program it is, and stopping it. Tests substitute a table of
/// their own; nothing is ever signalled there.
package struct ProcessTable: Sendable {
  /// The process running under `pid`, or `nil` when none does.
  package var identity: @Sendable (Int32) -> ProcessIdentity?
  /// The executable path of the process running under `pid`, or `nil` when unknown.
  package var executable: @Sendable (Int32) -> String?
  /// Stops the process named: SIGTERM, then SIGKILL after a grace period.
  ///
  /// Its identity is checked right before each signal; macOS has no process handle to signal,
  /// so a pid recycled in that instant cannot be ruled out entirely.
  package var terminate: @Sendable (ProcessIdentity) -> Void

  /// A table from its parts.
  package init(
    identity: @escaping @Sendable (Int32) -> ProcessIdentity?,
    executable: @escaping @Sendable (Int32) -> String?,
    terminate: @escaping @Sendable (ProcessIdentity) -> Void
  ) {
    self.identity = identity
    self.executable = executable
    self.terminate = terminate
  }

  /// The host's processes, read with `proc_pidinfo` / `proc_pidpath`.
  package static let live = Self(
    identity: liveIdentity, executable: liveExecutable,
    terminate: { process in
      // The pid is signalled only while it still names `process`: a reused pid never is.
      let pid = process.pid
      guard liveIdentity(pid) == process, kill(pid, SIGTERM) == 0 else { return }
      // Siril's own teardown gets the 2 s the session gives it (SirilPipeInstance).
      for _ in 0..<20 {
        guard liveIdentity(pid) == process else { return }
        usleep(100_000)
      }
      guard liveIdentity(pid) == process else { return }
      kill(pid, SIGKILL)
      // The kernel takes a moment to retire it: the caller checks it is gone right after.
      for _ in 0..<10 where liveIdentity(pid) == process { usleep(50_000) }
    })

  /// This process.
  package static var current: ProcessIdentity? { ProcessLiveness.current }

  /// The one liveness rule is ProjectKit's (`ProcessLiveness`, card 0147): pid and start time.
  private static func liveIdentity(_ pid: Int32) -> ProcessIdentity? {
    ProcessLiveness.stamp(of: pid)
  }

  private static func liveExecutable(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(
      validating: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
