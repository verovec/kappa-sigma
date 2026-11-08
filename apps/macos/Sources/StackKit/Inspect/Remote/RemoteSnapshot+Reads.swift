internal import Foundation
internal import ImageKit

// MARK: - The reads of a snapshot (card 0167)

extension RemoteSnapshot {
  /// Reads every FITS header (by growing ranges) and every side file the scan reads.
  ///
  /// A side file is a frame's SharpCap sidecar or an `info.txt`; `parallelism` reads at a time,
  /// `progress` hears the headers read. A side file that fails (or is too large) is absent for the
  /// scan and said as a warning (`sideFailures`); a header's error is the frame's skip warning.
  /// When no header at all could be read and the store reads the failures as the bucket's
  /// (`failsTheScan`, card 0186), the scan stops with a frame and the service's words: a key that
  /// may list but not read is never an empty « successful » scan, while one archived or
  /// encrypted frame among readable ones stays that frame's skip.
  mutating func readHeadersAndSideFiles(
    store: RemoteObjectStore, progress: @escaping @Sendable (ScanProgress) -> Void
  ) async throws {
    let sidecars = Set(listing.files.filter(InventoryBuilder.isFITS).map { $0 + ".txt" })
    // What a cache already answered (card 0168) is neither read nor counted as reading.
    let frames = listing.files.filter { InventoryBuilder.isFITS($0) && headers[$0] == nil }
    let sides = listing.files.filter {
      (sidecars.contains($0) || CaptureManifest.isManifest($0)) && contents[$0] == nil
    }
    progress(.reading(done: 0, total: frames.count))
    let objects = self.objects
    var done = 0
    try await Self.inParallel(frames + sides) { path -> (String, Read)? in
      guard let object = objects[path] else { return nil }
      if InventoryBuilder.isFITS(path) {
        return (path, .header(await Self.header(of: object, store: store)))
      }
      guard object.size <= Self.sideFileLimit else {
        return (path, .side(.failure(TooLarge(bytes: object.size))))
      }
      do {
        return (path, .side(.success(try await store.get(object.key, nil))))
      } catch {
        // A cancelled scan stops (URLSession says so with its own error): never a failed read.
        if Task.isCancelled { throw CancellationError() }
        return (path, .side(.failure(error)))
      }
    } collect: { path, read in
      switch read {
      case .header(let header):
        headers[path] = header
        done += 1
        if done % ScanProgress.readingStep == 0 || done == frames.count {
          progress(.reading(done: done, total: frames.count))
        }
      case .side(.success(let data)): contents[path] = data
      case .side(.failure(let error)): sideFailures[path] = String(describing: error)
      }
    }
    try refuseIfNothingRead(store)
  }

  /// Throws the bucket's refusal when every FITS header failed and one failed for the bucket.
  func refuseIfNothingRead(_ store: RemoteObjectStore) throws {
    let frames = listing.files.filter(InventoryBuilder.isFITS)
    guard !frames.isEmpty else { return }
    var refusal: (path: String, error: any Error)?
    for path in frames.sorted() {
      switch headers[path] {
      case .success?: return
      case .failure(let error)? where refusal == nil && store.failsTheScan(error):
        refusal = (path, error)
      default: continue
      }
    }
    guard let refusal else { return }
    throw InspectError.remoteUnreadable(
      path: refusal.path, reason: RemoteObjectStore.words(of: refusal.error))
  }

  /// Fetches the centred runs `asked` lists (path → largest count), one ranged read each; a frame
  /// whose run cannot be located or comes back short becomes `unreadable`, never a scan failure.
  @concurrent
  package mutating func fetchSamples(_ asked: [String: Int], store: RemoteObjectStore) async throws
  {
    var plans: [RunRead] = []
    for (path, count) in asked {
      guard let object = objects[path], case .success(let header)? = headers[path],
        let run = try? FITSFile.centerRun(of: header, maxCount: count)
      else {
        unreadable.insert(path)
        continue
      }
      let bytes = run.count * run.bytesPerValue
      let start = Int64(FITSFile.headerBytes(of: header) + run.first * run.bytesPerValue)
      plans.append(
        RunRead(
          path: path, key: object.key, range: start...(start + Int64(bytes) - 1), bytes: bytes))
    }
    let headers = self.headers
    try await Self.inParallel(plans) { plan -> (String, [Double]?)? in
      guard case .success(let header)? = headers[plan.path] else { return (plan.path, nil) }
      // A short answer (a truncated object) reads as `centerSample`'s truncated data: unreadable.
      let bytes: Data
      do {
        bytes = try await store.get(plan.key, plan.range)
      } catch {
        if Task.isCancelled { throw CancellationError() }
        return (plan.path, nil)
      }
      guard bytes.count == plan.bytes else { return (plan.path, nil) }
      return (plan.path, try? FITSFile.physicalValues(bytes, header: header))
    } collect: { path, values in
      // No further fetch for a frame that failed: a smaller run already held keeps answering.
      if let values { runs[path] = values } else { unreadable.insert(path) }
    }
  }

  /// The primary header of `object`: its first `headerChunk` bytes, extended until `END`.
  static func header(of object: RemoteObjectStore.Object, store: RemoteObjectStore) async
    -> Result<FITSHeader, any Error>
  {
    var data = Data()
    while true {
      let start = Int64(data.count)
      let end = min(start + headerChunk, object.size) - 1
      do {
        guard end >= start else { throw FITSError.noHeaderEnd }
        let chunk = try await store.get(object.key, start...end)
        // An empty answer to a range that is not (an object shrunk since the listing): no loop.
        guard !chunk.isEmpty else { throw FITSError.truncatedData }
        data.append(chunk)
        return .success(try FITSFile.parse(data).header)
      } catch FITSError.noHeaderEnd where Int64(data.count) < object.size {
        continue
      } catch {
        // Cancelled: the caller's group stops on its own check; the error is not the frame's.
        return .failure(Task.isCancelled ? CancellationError() : error)
      }
    }
  }

  /// A side file larger than `sideFileLimit`: not read, said as a warning.
  struct TooLarge: Error, CustomStringConvertible {
    let bytes: Int64
    var description: String { "\(bytes) bytes, larger than a sidecar or info.txt can be" }
  }

  /// One centred run to read: the frame, its key, the byte range, the bytes expected.
  struct RunRead: Sendable {
    let path: String
    let key: String
    let range: ClosedRange<Int64>
    let bytes: Int
  }

  /// One read's answer.
  enum Read: Sendable {
    case header(Result<FITSHeader, any Error>)
    case side(Result<Data, any Error>)
  }

  /// Runs `work` over `items` with at most `width` in flight, handing each answer to `collect`
  /// on the caller (cancellation checked between items); the first failure cancels the rest.
  static func inParallel<Item: Sendable, Answer: Sendable>(
    _ items: [Item], width: Int = parallelism,
    work: @escaping @Sendable (Item) async throws -> Answer?, collect: (Answer) throws -> Void
  ) async throws {
    // No slot would run nothing and drop every item without a word.
    precondition(width > 0, "inParallel needs at least one slot")
    try await withThrowingTaskGroup(of: Answer?.self) { group in
      var next = items.makeIterator()
      for _ in 0..<width {
        guard let item = next.next() else { break }
        group.addTask { try await work(item) }
      }
      while let answer = try await group.next() {
        try Task.checkCancellation()
        if let answer { try collect(answer) }
        if let item = next.next() { group.addTask { try await work(item) } }
      }
    }
  }
}
