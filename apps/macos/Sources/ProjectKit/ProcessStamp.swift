/// A process as the kernel knows it: its pid and the moment it started.
///
/// The start time is what makes a pid an identity: the kernel reuses pids, and a marker whose
/// owner died must not be kept alive by an unrelated process that later got the same pid.
public struct ProcessStamp: Codable, Hashable, Sendable {
  /// The kernel's process id.
  public let pid: Int32
  /// When the process started: whole seconds since 1970.
  public let startSeconds: UInt64
  /// When the process started: the microseconds past `startSeconds`.
  public let startMicroseconds: UInt64

  /// A stamp from its parts (`proc_bsdinfo.pbi_start_tvsec` / `_tvusec`).
  public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
    self.pid = pid
    self.startSeconds = startSeconds
    self.startMicroseconds = startMicroseconds
  }
}
