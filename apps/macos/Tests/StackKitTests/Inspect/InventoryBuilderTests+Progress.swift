import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

extension InventoryBuilderTests {
  /// `count` Ha lights (and a text file the walk lists but the scan skips).
  static func lights(_ count: Int, in name: String) throws -> URL {
    let dir = try InventoryBuilderFallbackTests.folder(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for index in 0..<count {
      try TestFITS.write(
        "ha_\(index).fits", in: dir, pixel: 1200,
        cards: Self.asi("'Light Frame'", filter: "'Ha'", exptime: "300.0"))
    }
    try Data("notes".utf8).write(to: dir.appendingPathComponent("notes.txt"))
    return dir
  }

  @Test(
    "the scan reports the FITS total, a monotonic count ending at it, then classifying",
    .scratchDirectory, arguments: [0, 1, 33, 70])
  func testScanReportsProgress(files: Int) throws {
    let dir = try Self.lights(files, in: "progress")
    let seen = Mutex<[ScanProgress]>([])
    let reported = try Self.builder.scan(paths: [dir.path]) { progress in
      seen.withLock { $0.append(progress) }
    }
    let events = seen.withLock { $0 }
    #expect(events.first == .listing && events.last == .classifying)
    let reading = events.compactMap { event -> (done: Int, total: Int)? in
      if case .reading(let done, let total) = event { (done, total) } else { nil }
    }
    #expect(reading.allSatisfy { $0.total == files })
    #expect(reading.map(\.done) == reading.map(\.done).sorted())
    #expect(reading.first?.done == 0 && reading.last?.done == files)
    #expect(reported == (try Self.scan(dir)), "observation only: the same inventory")
  }

  @Test("nothing is reported once the scan is cancelled", .scratchDirectory)
  func testCancelledScanStopsReporting() async throws {
    let dir = try Self.lights(40, in: "cancel")
    let seen = Mutex<[ScanProgress]>([])
    let path = dir.path
    let task = Task {
      try Self.builder.scan(paths: [path]) { progress in
        seen.withLock { $0.append(progress) }
        // Cancelled from inside, at the first count: the next file checks it and stops.
        if case .reading(let done, _) = progress, done > 0 {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    let events = seen.withLock { $0 }
    #expect(!events.contains(.classifying))
    #expect(events.last == .reading(done: 32, total: 40))
  }
}
