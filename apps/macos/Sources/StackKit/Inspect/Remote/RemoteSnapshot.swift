package import Foundation
package import ImageKit
internal import Synchronization

/// An S3 prefix read in advance for the synchronous scan (card 0167): the listing as virtual paths
/// `s3://<bucket>/<key>`, every FITS header (read by ranges, grown until `END`), the small side
/// files (SharpCap sidecars, `info.txt`) and the centred pixel runs the scan asked for.
///
/// Whole frames are never downloaded (PO 01/11): a check that needs a frame's planes is not run
/// and its frame is named in `Inventory.notCheckedRemotely` (R2: shown, never silently passed).
package struct RemoteSnapshot: Sendable {
  /// The first bytes read of a frame, then each extension until the header's `END`.
  static let headerChunk: Int64 = 64 << 10
  /// A side file larger than this is no sidecar or manifest: never downloaded.
  static let sideFileLimit: Int64 = 1 << 20
  /// Requests in flight at once.
  static let parallelism = 8

  /// The virtual root of the scan: `s3://<bucket>/<prefix>` without its trailing `/`.
  package let root: String
  /// The walk of the prefix, in virtual paths.
  package let listing: InspectWalk.Listing
  /// The object behind each virtual path.
  let objects: [String: RemoteObjectStore.Object]
  /// Each FITS frame's header, or the error reading it gave (a skip warning, as on disk).
  var headers: [String: Result<FITSHeader, any Error>] = [:]
  /// The side files' bytes.
  var contents: [String: Data] = [:]
  /// The centred run read of each frame, at the largest count asked.
  var runs: [String: [Double]] = [:]

  /// The virtual path of `key` in `bucket`.
  package static func path(bucket: String, key: String) -> String {
    "s3://" + bucket + "/" + key
  }

  /// Lists `prefix` of `store` and reads every FITS header and side file under it; `progress`
  /// hears the listing, then the headers read.
  @concurrent
  package static func load(
    store: RemoteObjectStore, prefix: String,
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Self {
    progress(.listing)
    let folder = prefix.isEmpty || prefix.hasSuffix("/") ? prefix : prefix + "/"
    let found = try await store.list(folder)
    let root = path(bucket: store.bucket, key: String(folder.dropLast(folder.isEmpty ? 0 : 1)))
    var objects: [String: RemoteObjectStore.Object] = [:]
    for object in found where object.key.hasPrefix(folder) {
      objects[path(bucket: store.bucket, key: object.key)] = object
    }
    let listing = InspectWalk.listing(
      keys: found.filter { $0.key.hasPrefix(folder) }.map {
        String($0.key.dropFirst(folder.count))
      },
      under: root, skippingOutput: true)
    var snapshot = Self(root: root, listing: listing, objects: objects)
    try await snapshot.readHeadersAndSideFiles(store: store, progress: progress)
    return snapshot
  }

  /// The source the scan reads: this snapshot's listing, headers and side files.
  package var source: FrameSource {
    let snapshot = self
    return FrameSource(
      walk: { root, _ in
        guard root == snapshot.root || root == snapshot.root + "/" else {
          return InspectWalk.Listing()
        }
        return snapshot.listing
      },
      header: { path in
        guard let header = snapshot.headers[path] else { throw NotRead(path: path) }
        return try header.get()
      },
      contents: { snapshot.contents[$0] })
  }

  /// The pixels the scan reads: centred runs this snapshot holds; whatever else is asked is told
  /// to `asked` (a run to fetch, a frame whose planes are never read) and not answered.
  package func pixels(_ asked: Asked) -> PixelReader {
    let snapshot = self
    return PixelReader(
      planes: { path in
        asked.planes(path)
        throw NotRead(path: path)
      },
      centerSample: { path, count in
        guard let values = try snapshot.sample(path, count: count) else {
          asked.sample(path, count: count)
          throw NotRead(path: path)
        }
        return values
      })
  }

  /// The centred run of `count` values of `path`, cut from the larger run held, or `nil`.
  func sample(_ path: String, count: Int) throws -> [Double]? {
    guard let held = runs[path], case .success(let header)? = headers[path] else { return nil }
    let wanted = try FITSFile.centerRun(of: header, maxCount: count)
    let have = try FITSFile.centerRun(of: header, maxCount: held.count)
    guard wanted.count <= have.count else { return nil }
    let offset = wanted.first - have.first
    return Array(held[offset..<offset + wanted.count])
  }

  /// What the scan asked of the pixel reader that the snapshot could not answer.
  package final class Asked: Sendable {
    private let state = Mutex((planes: Set<String>(), samples: [String: Int]()))

    /// An empty record.
    package init() {}

    /// The frames whose planes a check asked for.
    package var framesNeedingPlanes: [String] { state.withLock { $0.planes.sorted() } }
    /// The centred runs to fetch: the largest count asked per frame.
    package var missingSamples: [String: Int] { state.withLock { $0.samples } }

    func planes(_ path: String) { state.withLock { _ = $0.planes.insert(path) } }

    func sample(_ path: String, count: Int) {
      state.withLock { $0.samples[path] = max($0.samples[path] ?? 0, count) }
    }
  }

  /// A read the snapshot holds no answer for.
  struct NotRead: Error, CustomStringConvertible {
    let path: String
    var description: String { "not read from S3: \(path)" }
  }
}
