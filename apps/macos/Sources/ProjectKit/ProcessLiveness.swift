internal import Darwin

/// Whether a process still runs (card 0147): the one `proc_pidinfo` rule, read by the project
/// owner marker here and by StackKit's scratch owners.
package enum ProcessLiveness {
  /// The stamp of `pid` while it runs; `nil` for a pid that is not one, a process gone, or a
  /// zombie (it keeps its pid until reaped but runs nothing: it owns nothing any more).
  package static func stamp(of pid: Int32) -> ProcessStamp? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    // The kernel fills `info` for the pid; a reused buffer of the exact struct size (unsafe API).
    guard pid > 0, unsafe proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
      return nil
    }
    guard info.pbi_status != UInt32(SZOMB) else { return nil }
    return ProcessStamp(
      pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
  }

  /// This process.
  package static var current: ProcessStamp? { stamp(of: getpid()) }

  /// Whether the process `stamp` names still runs: same pid, same start.
  package static func isRunning(_ stamp: ProcessStamp) -> Bool {
    self.stamp(of: stamp.pid) == stamp
  }
}
