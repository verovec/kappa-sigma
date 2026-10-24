/// A process as the kernel knows it: its pid and the moment it started.
///
/// The start time is what makes a pid an identity: the kernel reuses pids, and a scratch folder
/// whose owner died must not be kept alive by an unrelated process that later got the same pid.
package struct ProcessIdentity: Codable, Hashable, Sendable {
  /// The kernel's process id.
  package var pid: Int32
  /// When the process started: whole seconds since 1970.
  package var startSeconds: UInt64
  /// When the process started: the microseconds past `startSeconds`.
  package var startMicroseconds: UInt64

  /// An identity from its parts (`proc_bsdinfo.pbi_start_tvsec` / `_tvusec`).
  package init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
    self.pid = pid
    self.startSeconds = startSeconds
    self.startMicroseconds = startMicroseconds
  }
}
