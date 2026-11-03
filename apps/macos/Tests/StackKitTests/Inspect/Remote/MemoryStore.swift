import Foundation
import StackKit
import Synchronization

/// An S3 bucket in memory for the remote scan tests: the files of a local tree under a prefix,
/// every `get` recorded (key, range) so a test can count what was downloaded.
final class MemoryStore: Sendable {
  let bucket: String
  let objects: [String: Data]
  private let log = Mutex<[(key: String, range: ClosedRange<Int64>?)]>([])

  init(bucket: String = "astro", objects: [String: Data]) {
    self.bucket = bucket
    self.objects = objects
  }

  /// The files under `root`, as keys `prefix` + their path relative to `root`.
  convenience init(tree root: URL, prefix: String, bucket: String = "astro") throws {
    var objects: [String: Data] = [:]
    let base = root.standardizedFileURL.path
    let walker = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey])
    while let url = walker?.nextObject() as? URL {
      guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        continue
      }
      let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
      objects[prefix + relative] = try Data(contentsOf: url)
    }
    self.init(bucket: bucket, objects: objects)
  }

  /// Every read, in order.
  var gets: [(key: String, range: ClosedRange<Int64>?)] { log.withLock { $0 } }

  var store: RemoteObjectStore {
    RemoteObjectStore(
      bucket: bucket,
      list: { prefix in
        self.objects.keys.filter { $0.hasPrefix(prefix) }.sorted().map { key in
          RemoteObjectStore.Object(
            key: key, size: Int64(self.objects[key]?.count ?? 0), etag: "e\(key.count)")
        }
      },
      get: { key, range in
        self.log.withLock { $0.append((key, range)) }
        guard let data = self.objects[key] else { throw CocoaError(.fileNoSuchFile) }
        guard let range else { return data }
        let upper = min(Int(range.upperBound), data.count - 1)
        return data.subdata(in: Int(range.lowerBound)..<(upper + 1))
      })
  }
}
