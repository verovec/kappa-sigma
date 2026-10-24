internal import Darwin
internal import Foundation

/// What the sweep may ask of the system's processes.
///
/// Who runs under a pid, which program it is, and stopping it. Tests substitute a table of
/// their own; nothing is ever signalled there.
package struct ProcessTable: Sendable {
  /// The process running under `pid`, or `nil` when none does.
  package var identity: @Sendable (Int32) -> ProcessIdentity?
  /// The executable path of the process running under `pid`, or `nil` when unknown.
  package var executable: @Sendable (Int32) -> String?
  /// Stops the process `identity` names: SIGTERM, then SIGKILL when it is still there after a
  /// grace period; each signal only while its pid still runs the process started then.
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
  package static var current: ProcessIdentity? { live.identity(getpid()) }

  private static func liveIdentity(_ pid: Int32) -> ProcessIdentity? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    // A zombie keeps its pid until reaped but runs nothing: it owns nothing any more.
    guard info.pbi_status != UInt32(SZOMB) else { return nil }
    return ProcessIdentity(
      pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
  }

  private static func liveExecutable(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(
      validating: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
