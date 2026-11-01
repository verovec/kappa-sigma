internal import Foundation
internal import ImageKit

// MARK: - The reads of a snapshot (card 0167)

extension RemoteSnapshot {
  /// Reads every FITS header (by growing ranges) and every small side file, `parallelism` at a
  /// time; `progress` hears the headers read.
  mutating func readHeadersAndSideFiles(
    store: RemoteObjectStore, progress: @escaping @Sendable (ScanProgress) -> Void
  ) async throws {
    let frames = listing.files.filter(InventoryBuilder.isFITS)
    let sides = listing.files.filter {
      !InventoryBuilder.isFITS($0) && (objects[$0]?.size ?? .max) <= Self.sideFileLimit
    }
    progress(.reading(done: 0, total: frames.count))
    let objects = self.objects
    var done = 0
    try await Self.inParallel(frames + sides) { path -> (String, Read)? in
      guard let object = objects[path] else { return nil }
      if InventoryBuilder.isFITS(path) {
        return (path, .header(await Self.header(of: object, store: store)))
      }
      return (path, .side(try await store.get(object.key, nil)))
    } collect: { path, read in
      switch read {
      case .header(let header):
        headers[path] = header
        done += 1
        if done % ScanProgress.readingStep == 0 || done == frames.count {
          progress(.reading(done: done, total: frames.count))
        }
      case .side(let data): contents[path] = data
      }
    }
  }

  /// Fetches the centred runs `asked` lists (path → largest count), one ranged read each.
  @concurrent
  package mutating func fetchSamples(_ asked: [String: Int], store: RemoteObjectStore) async throws
  {
    let plans = try asked.compactMap { path, count -> (String, String, ClosedRange<Int64>)? in
      guard let object = objects[path], case .success(let header)? = headers[path] else {
        return nil
      }
      let run = try FITSFile.centerRun(of: header, maxCount: count)
      let start = Int64(FITSFile.headerBytes(of: header) + run.first * run.bytesPerValue)
      return (path, object.key, start...(start + Int64(run.count * run.bytesPerValue) - 1))
    }
    let headers = self.headers
    try await Self.inParallel(plans) { plan -> (String, [Double])? in
      guard case .success(let header)? = headers[plan.0] else { return nil }
      let bytes = try await store.get(plan.1, plan.2)
      return (plan.0, try FITSFile.physicalValues(bytes, header: header))
    } collect: { path, values in
      runs[path] = values
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
        data.append(try await store.get(object.key, start...end))
        return .success(try FITSFile.parse(data).header)
      } catch FITSError.noHeaderEnd where Int64(data.count) < object.size {
        continue
      } catch {
        return .failure(error)
      }
    }
  }

  /// One read's answer.
  enum Read: Sendable {
    case header(Result<FITSHeader, any Error>)
    case side(Data)
  }

  /// Runs `work` over `items` with at most `parallelism` in flight, handing each answer to
  /// `collect` on the caller (cancellation checked between items).
  static func inParallel<Item: Sendable, Answer: Sendable>(
    _ items: [Item], work: @escaping @Sendable (Item) async throws -> Answer?,
    collect: (Answer) throws -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: Answer?.self) { group in
      var next = items.makeIterator()
      for _ in 0..<parallelism {
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
