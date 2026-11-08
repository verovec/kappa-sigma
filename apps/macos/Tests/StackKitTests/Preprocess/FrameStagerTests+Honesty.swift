import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0186: a lane stacks the bytes its run listed (an object uploaded again since fails the
/// lane, named), a listing that fails is said, and a lane's downloads run several at once
/// without changing a frame's name.
@Suite("FrameStager — the bytes the run listed, several at once")
struct FrameStagerHonestyTests {
  typealias FakeBucket = FrameStagerTests.FakeBucket

  @Test(
    "an object uploaded again since the run listed it fails the lane, named",
    .scratchDirectory, arguments: [true, false])
  func testChangedObjectFailsTheLane(fetching: Bool) async throws {
    let root = try ScratchDirectory.url
    let bucket = FakeBucket(objects: ["M31/r_1.fits": Data("one".utf8)], fetching: fetching)
    let path = "s3://astro/M31/r_1.fits"
    let listed = try await FrameStager(stores: [bucket.store]).identities(of: [path])
    bucket.replace("M31/r_1.fits", with: Data("one, again".utf8))
    let staged = root.appendingPathComponent("light_L")

    await #expect {
      try await FrameStager(stores: [bucket.store], expected: listed).stage([path], into: staged)
    } throws: { error in
      guard case PreprocessError.remoteFrameUnavailable(let named, _) = error else { return false }
      return named == path
    }
    let left = (try? FileManager.default.contentsOfDirectory(atPath: staged.path)) ?? []
    #expect(left.isEmpty, "neither the changed frame nor a .part: \(left)")
  }

  @Test("an object unchanged since the listing is staged as before", .scratchDirectory)
  func testUnchangedObjectIsStaged() async throws {
    let root = try ScratchDirectory.url
    let bucket = FakeBucket(objects: ["M31/r_1.fits": Data("one".utf8)])
    let path = "s3://astro/M31/r_1.fits"
    let listed = try await FrameStager(stores: [bucket.store]).identities(of: [path])

    let staged = try await FrameStager(stores: [bucket.store], expected: listed).stage(
      [path], into: root.appendingPathComponent("light_L"))

    #expect(staged.identities == listed)
  }

  @Test("a folder holding more objects than a run lists is refused, named")
  func testIdentitiesBeyondTheCapAreRefused() async throws {
    let objects = (0...RemoteSnapshot.maxObjects).map {
      RemoteObjectStore.Object(key: "M31/f_\($0).fits", size: 1, etag: "e")
    }
    let store = RemoteObjectStore(bucket: "astro", list: { _ in objects }, get: { _, _ in Data() })

    await #expect(throws: PreprocessError.self) {
      _ = try await FrameStager(stores: [store]).identities(of: ["s3://astro/M31/f_1.fits"])
    }
  }

  @Test(
    "downloads run several at once and every frame keeps its positional name", .scratchDirectory,
    .timeLimit(.minutes(1)))
  func testParallelDownloadsKeepPositionalNames() async throws {
    let root = try ScratchDirectory.url
    let local = try FrameStagerTests.localFrames(1, in: root.appendingPathComponent("capture"))
    let count = FrameStager.parallelism * 2
    let objects = Dictionary(
      uniqueKeysWithValues: (0..<count).map { ("M31/r_\($0).fits", Data("remote \($0)".utf8)) })
    let gate = Gate(width: FrameStager.parallelism)
    let store = RemoteObjectStore(
      bucket: "astro", list: { _ in [] },
      get: { key, _ in
        // The first downloads wait until `parallelism` are in flight: a serial stager never
        // gets past the first one (the time limit says so), a parallel one does at once.
        await gate.arrive()
        return objects[key] ?? Data()
      })
    let paths = [local[0]] + (0..<count).map { "s3://astro/M31/r_\($0).fits" }
    let folder = root.appendingPathComponent("light_L")

    let staged = try await FrameStager(stores: [store]).stage(paths, into: folder)

    #expect(
      FrameStager.parallelism == 4, "the card's four in flight: one would pass the gate alone")
    #expect(staged.remote == count)
    for index in 0..<count {
      let name = String(format: "%05d_r_\(index).fits", index + 2)
      #expect(
        try Data(contentsOf: folder.appendingPathComponent(name)) == Data("remote \(index)".utf8),
        "\(name) holds its own frame, whatever order the downloads ended in")
    }
    #expect(staged.files.map(\.lastPathComponent).first == "00001_l_0.fits")
  }

  @Test("a cancelled lane leaves no .part while several downloads are in flight", .scratchDirectory)
  func testCancelLeavesNoPartWhileParallel() async throws {
    let root = try ScratchDirectory.url
    let started = Gate(width: FrameStager.parallelism)
    let store = RemoteObjectStore(
      bucket: "astro", list: { _ in [] },
      get: { _, _ in
        await started.arrive()
        // Held until cancelled: the lane is stopped with every slot busy. A stream nothing
        // yields to ends only when its task is cancelled.
        let (held, open) = AsyncStream<Void>.makeStream()
        for await _ in held {}
        open.finish()
        try Task.checkCancellation()
        return Data()
      })
    let paths = (0..<(FrameStager.parallelism * 2)).map { "s3://astro/M31/r_\($0).fits" }
    let folder = root.appendingPathComponent("light_L")

    let lane = Task { try await FrameStager(stores: [store]).stage(paths, into: folder) }
    await started.passed()
    lane.cancel()

    await #expect(throws: CancellationError.self) { _ = try await lane.value }
    let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    #expect(left.allSatisfy { !$0.hasSuffix(".part") }, "\(left)")
  }
}

/// Releases everyone once `width` have arrived; `passed` waits for that moment.
actor Gate {
  private let width: Int
  private var arrived = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(width: Int) { self.width = width }

  func arrive() async {
    arrived += 1
    if arrived >= width {
      waiting.forEach { $0.resume() }
      waiting.removeAll()
      return
    }
    await withCheckedContinuation { waiting.append($0) }
  }

  func passed() async {
    guard arrived < width else { return }
    await withCheckedContinuation { waiting.append($0) }
  }
}
