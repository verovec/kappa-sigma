import AstroStackApp
import CryptoKit
import Foundation
import ImageKit
import ProjectKit
import RemoteKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Cards 0154 and 0183: a night read from a bucket stacks to the same masters and the same bundle
/// as the same night on this Mac — Siril does the pixel math either way — going the app's own way:
/// the prefix recorded as a project source, scanned where it stands (`remotePlanning`), its frames
/// staged through the stores of the project's sources (`runStores`). A second run over the same
/// unchanged frames reuses the masters the first built and downloads no calibration frame
/// (card 0181).
///
/// Needs a real Siril and an S3 endpoint (`just s3-live`): it skips, saying which, without either.
@Suite(
  "Live remote pipeline: a bucket's night equals the same night on disk",
  .liveS3,
  .liveFixtures, .tags(.live), .serialized, .timeLimit(.minutes(10)))
struct RemotePipelineLiveTests {
  /// One synthetic night on disk and in the bucket under a prefix of this run alone.
  struct Night {
    let live: LiveS3Environment
    let client: S3Client
    let root: URL
    let input: URL
    let prefix: String
    let binary: String

    /// The night (card 0142's L-only rig: flats, darks, bias, lights) written on disk and
    /// uploaded under a prefix of its own, keeping its folders; `body` runs over it, and the
    /// prefix is removed afterwards whether a step threw or not.
    static func with(_ body: (Self) async throws -> Void) async throws {
      let live = try #require(LiveS3Environment.current)
      let client = live.client()
      try await live.ensureBucket(client)
      try await live.sweepOnce(client: client)
      let root = try ScratchDirectory.url.appendingPathComponent("n1/n2/n3/remote-live")
      let night = Self(
        live: live, client: client, root: root, input: root.appendingPathComponent("in"),
        prefix: LiveS3Environment.runPrefix(), binary: try SirilTool.locate())
      do {
        try await night.upload()
        try await body(night)
      } catch {
        await night.clean()
        throw error
      }
      await night.clean()
    }

    /// Writes the night under `input` and uploads every file of it under `prefix`.
    func upload() async throws {
      for file in try SyntheticCapture(.lOnly).write(under: input) {
        let relative = String(file.path.dropFirst(input.path.count + 1))
        _ = try await client.upload(file: file, bucket: live.bucket, key: prefix + relative)
      }
    }

    /// The run of `inventory` into `out-<run>` / `work-<run>` over `stores`.
    func run(
      _ inventory: Inventory, _ run: String, stores: [RemoteObjectStore] = [],
      library: [CalibrationMaster] = []
    ) async throws -> PreprocessResult {
      let work = root.appendingPathComponent("work-\(run)")
      var request = PreprocessRequest(
        inventory: inventory, output: root.appendingPathComponent("out-\(run)"), work: work,
        runID: run, mode: .deepsky, library: library)
      request.remoteStores = stores
      let tools = Preprocessor.Tools(
        runner: SirilRunner.make(mode: .default, binary: binary, work: work))
      return try await Preprocessor(tools: tools).perform(request) { _ in }
    }

    /// The bucket's night as the import sheet plans it, recorded in a new project; the stores
    /// its run reads, each download counted by key.
    func imported() async throws -> (
      inventory: Inventory, stores: [RemoteObjectStore], downloads: Downloads
    ) {
      let project = try ProjectPackage.create(
        at: root.appendingPathComponent("P-\(UUID().uuidString).astrostack"))
      defer { try? project.close() }
      let connection = UUID()
      let target = RemoteImportTarget(
        connectionID: connection, bucket: live.bucket, prefix: String(prefix.dropLast()))
      _ = try project.store.addSource(
        remote: connection.uuidString, bucket: target.bucket, prefix: target.prefix)
      // An empty library: the bucket's frames build the masters, nothing of this tree is reused.
      let library = root.appendingPathComponent("library-\(UUID().uuidString)")
      let planning = ImportPlanning.remotePlanning(
        store: project.store, index: LibraryIndex(store: project.store, folder: library),
        client: { [client] _ in client })
      let plan = try await planning(target, ImportRequest(paths: [target.path])) { _ in }
      let downloads = Downloads()
      let stores = ImportPlanning.runStores(try project.store.sources()) { [client] _ in client }
      return (plan.inventory, stores.map(downloads.counting), downloads)
    }

    /// Removes this run's prefix.
    func clean() async {
      do { try await live.removePrefix(prefix, client: client) } catch {
        Issue.record("could not remove \(prefix): \(error)")
      }
    }
  }

  /// The keys a run downloaded, in order.
  final class Downloads: Sendable {
    let keys = Mutex<[String]>([])

    /// `store` with every whole-frame download recorded.
    func counting(_ store: RemoteObjectStore) -> RemoteObjectStore {
      RemoteObjectStore(
        bucket: store.bucket, list: store.list, get: store.get,
        fetch: { [self] key, destination in
          keys.withLock { $0.append(key) }
          return try await store.download(key, to: destination)
        })
    }

    /// Downloads of calibration frames (flats, darks, bias folders of the synthetic rig).
    var calibration: [String] {
      keys.withLock { $0 }.filter { key in
        ["/flats/", "/darks/", "/bias/"].contains { key.contains($0) }
      }
    }
  }

  /// The sha256 of the data unit of every `master_*.fits` of a run, by file name: Siril stamps
  /// `DATE` (the second it wrote the file) in every header, so two runs of the same frames differ
  /// there and nowhere else (the oracles of 0044 hash the same way, `PreprocessLiveTests`).
  static func masterDigests(in folder: URL) throws -> [String: String] {
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    var digests: [String: String] = [:]
    for name in names.sorted() where name.hasPrefix("master_") && name.hasSuffix(".fits") {
      let body = try FITSFile.read(at: folder.appendingPathComponent(name)).dataUnit
      digests[name] = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }
    return digests
  }

  /// Each set's frame count, by set.
  static func counts(_ inventory: Inventory) -> [String] {
    inventory.sets.map { "\($0.key.id): \($0.frames.count)" }.sorted()
  }

  /// `bundle` with the run id (the one field two runs of one night never share) set to `run`.
  static func normalised(_ bundle: LinearBundle?, run: String) -> LinearBundle? {
    guard var bundle else { return nil }
    bundle.runID = run
    return bundle
  }

  @Test(
    "testRemoteNightEqualsLocal: same masters and bundle, from the bucket or from the disk",
    .scratchDirectory)
  func testRemoteNightEqualsLocal() async throws {
    try await Night.with { night in try await Self.remoteEqualsLocal(night) }
  }

  /// The local run, the import and the bucket run of `night`, compared.
  static func remoteEqualsLocal(_ night: Night) async throws {
    let local = try InventoryBuilder().scan(paths: [night.input.path])
    let reference = try await night.run(local, "R_local")

    let remote = try await night.imported()
    #expect(
      Self.counts(remote.inventory) == Self.counts(local),
      "the bucket scan finds the frames the disk scan finds")
    let result = try await night.run(remote.inventory, "R_remote", stores: remote.stores)

    let localDigests = try Self.masterDigests(in: night.root.appendingPathComponent("out-R_local"))
    #expect(!localDigests.isEmpty, "the local run wrote masters")
    let remoteDigests = try Self.masterDigests(
      in: night.root.appendingPathComponent("out-R_remote"))
    #expect(
      remoteDigests == localDigests,
      "same frames, same scripts, same masters — Siril does the pixel math")
    #expect(reference.bundle != nil)
    #expect(
      Self.normalised(result.bundle, run: "R") == Self.normalised(reference.bundle, run: "R"),
      "bundle.json: same grid, layers, files and statistics")
    #expect(!remote.downloads.keys.withLock { $0 }.isEmpty, "the frames came from the bucket")
    #expect(
      !FileManager.default.fileExists(
        atPath: night.root.appendingPathComponent("work-R_remote/light_L").path),
      "the lane's downloads went with it")
  }

  @Test(
    "testRemoteRerunReusesItsMasters: the second run downloads no calibration frame",
    .scratchDirectory)
  func testRemoteRerunReusesItsMasters() async throws {
    try await Night.with { night in try await Self.rerunReuses(night) }
  }

  /// Two runs of `night` from the bucket, the second over the first one's masters.
  static func rerunReuses(_ night: Night) async throws {
    let first = try await night.imported()
    let built = try await night.run(first.inventory, "R1", stores: first.stores)
    #expect(!first.downloads.calibration.isEmpty, "the first run reads the calibration frames")

    // The next run, as Run does: the bucket scanned and listed again, the masters in the library.
    let second = try await night.imported()
    let library = built.masters.map { master in
      var kept = master
      kept.fromLibrary = true
      return kept
    }
    let rerun = try await night.run(
      second.inventory, "R2", stores: second.stores, library: library)

    #expect(
      rerun.warnings.contains { $0.contains("reused library master") },
      "the .sig proves the bucket's bytes: \(rerun.warnings)")
    #expect(
      second.downloads.calibration.isEmpty,
      "no calibration frame downloaded again: \(second.downloads.calibration)")
  }
}
