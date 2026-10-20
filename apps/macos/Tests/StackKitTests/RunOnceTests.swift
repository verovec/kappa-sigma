import StackKit
import Synchronization
import Testing

/// `RunOnce` makes a teardown idempotent across threads: the Siril pipe instance closes its FIFO
/// handles from both the session and its deinit, and two overlapping closes of one descriptor
/// number can close a descriptor another component reused meanwhile (the swift-subprocess
/// "FileDescriptor N is already closed" CI crash).
@Suite("RunOnce — a teardown runs exactly once, whoever calls it")
struct RunOnceTests {
  @Test("a thousand concurrent calls run the body once")
  func testRunOnce_concurrentCalls() async {
    let count = Mutex(0)
    let once = RunOnce { count.withLock { $0 += 1 } }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<1000 { group.addTask { once.run() } }
    }
    #expect(count.withLock { $0 } == 1)
  }

  @Test("later calls return without running the body again")
  func testRunOnce_sequentialCalls() {
    let count = Mutex(0)
    let once = RunOnce { count.withLock { $0 += 1 } }
    once.run()
    once.run()
    #expect(count.withLock { $0 } == 1)
    #expect(once.hasRun)
  }
}
