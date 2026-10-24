import StackKit
import Synchronization

/// A process table the test writes: the processes running, their executables, and every pid the
/// code under test asked to terminate (nothing is ever signalled).
final class FakeProcessTable: Sendable {
  private let running: Mutex<[Int32: (ProcessIdentity, String)]>
  private let terminated = Mutex<[Int32]>([])

  /// `running` processes, each with `executable` unless `executables` names another.
  init(
    running: [ProcessIdentity], executables: [Int32: String] = [:],
    executable: String = "/Applications/Siril.app/Contents/MacOS/siril-cli"
  ) {
    self.running = Mutex(
      Dictionary(
        uniqueKeysWithValues: running.map { ($0.pid, ($0, executables[$0.pid] ?? executable)) }))
  }

  /// The pids `terminate` was called with, in order.
  var terminatedPIDs: [Int32] { terminated.withLock { $0 } }

  /// The table as the code under test reads it; a terminated process stops running.
  var table: ProcessTable {
    ProcessTable(
      identity: { pid in self.running.withLock { $0[pid]?.0 } },
      executable: { pid in self.running.withLock { $0[pid]?.1 } },
      terminate: { process in
        let pid = process.pid
        self.terminated.withLock { $0.append(pid) }
        _ = self.running.withLock { $0.removeValue(forKey: pid) }
      })
  }
}
