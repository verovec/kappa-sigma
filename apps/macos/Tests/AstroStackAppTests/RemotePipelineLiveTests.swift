import AstroStackApp
import CryptoKit
import Foundation
import RemoteKit
import StackKit
import TestSupport
import Testing

/// Where this card's live run reads from: a local `minio server` named by
/// `ASTROSTACK_S3_LIVE_ENDPOINT` (`just s3-live`), never a real bucket by default.
enum LiveRemoteNight {
  struct Configuration {
    let client: S3Client
    let bucket: String
    /// A prefix of this run alone, removed at the end.
    let prefix: String
  }

  /// `nil` (the suite skips) without the endpoint variable, or under `ASTROSTACK_SKIP_LIVE=1`.
  static var configuration: Configuration? {
    let env = ProcessInfo.processInfo.environment
    guard env["ASTROSTACK_SKIP_LIVE"] != "1",
      let text = env["ASTROSTACK_S3_LIVE_ENDPOINT"], let url = URL(string: text),
      let endpoint = try? S3Endpoint(
        url: url, region: env["ASTROSTACK_S3_LIVE_REGION"] ?? "us-east-1", addressing: .pathStyle)
    else { return nil }
    let credentials = S3Credentials(
      accessKey: env["ASTROSTACK_S3_LIVE_ACCESS_KEY"] ?? "minioadmin",
      secretKey: env["ASTROSTACK_S3_LIVE_SECRET_KEY"] ?? "minioadmin")
    return Configuration(
      client: S3Client(
        endpoint: endpoint, credentials: credentials, transport: HTTPTransport.urlSession()),
      bucket: env["ASTROSTACK_S3_LIVE_BUCKET"] ?? "astrostack-live",
      prefix: "card0154/\(UUID().uuidString)/")
  }
}

/// Card 0154: a night read from a bucket stacks to the same masters as the same night on this
/// Mac — Siril does the pixel math either way, and the staged frames are byte-identical copies
/// under the same positional names.
///
/// Needs a real Siril and a local MinIO: it skips, saying which, without either.
@Suite(
  "Live remote pipeline: a bucket's night equals the same night on disk",
  .enabled(
    if: LiveRemoteNight.configuration != nil,
    "ASTROSTACK_S3_LIVE_ENDPOINT unset (just s3-live)"),
  .liveFixtures, .tags(.live), .serialized, .timeLimit(.minutes(10)))
struct RemotePipelineLiveTests {
  /// The sha256 of every `master_*.fits` of a run, by file name.
  static func masterDigests(in folder: URL) throws -> [String: String] {
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    var digests: [String: String] = [:]
    for name in names.sorted() where name.hasPrefix("master_") && name.hasSuffix(".fits") {
      let bytes = try Data(contentsOf: folder.appendingPathComponent(name))
      digests[name] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    return digests
  }

  @Test("testRemoteNightEqualsLocal: the same masters, from the bucket or from the disk")
  func testRemoteNightEqualsLocal() async throws {
    let live = try #require(LiveRemoteNight.configuration)
    let binary = try SirilTool.locate()
    let root = try ScratchDirectory.url.appendingPathComponent("n1/n2/n3/remote-live")
    let input = root.appendingPathComponent("in")
    // A synthetic L-only night (card 0142's fixture): small, and real FITS for real Siril.
    try SyntheticCapture(.lOnly).write(under: input)
    let local = try InventoryBuilder().scan(paths: [input.path])

    // The reference run, from this Mac.
    let localOut = root.appendingPathComponent("out-local")
    let localWork = root.appendingPathComponent("work-local")
    let tools = Preprocessor.Tools(
      runner: SirilRunner.make(mode: .default, binary: binary, work: localWork))
    _ = try await Preprocessor(tools: tools).perform(
      PreprocessRequest(
        inventory: local, output: localOut, work: localWork, runID: "R_local", mode: .deepsky)
    ) { _ in }

    // The same frames, uploaded, then scanned and run from the bucket.
    var remoteSets: [FrameSet] = []
    for set in local.sets {
      var frames: [CaptureFrame] = []
      for frame in set.frames {
        let key = live.prefix + PathMeta.baseName(frame.path)
        _ = try await live.client.upload(
          file: URL(fileURLWithPath: frame.path), bucket: live.bucket, key: key)
        var moved = frame
        moved.path = "s3://\(live.bucket)/\(key)"
        frames.append(moved)
      }
      remoteSets.append(FrameSet(key: set.key, frames: frames, indices: set.indices))
    }
    var remote = local
    remote.sets = remoteSets
    remote.root = "s3://\(live.bucket)/\(live.prefix.dropLast())"
    let remoteOut = root.appendingPathComponent("out-remote")
    let remoteWork = root.appendingPathComponent("work-remote")
    var request = PreprocessRequest(
      inventory: remote, output: remoteOut, work: remoteWork, runID: "R_remote", mode: .deepsky)
    request.remoteStores = [.s3(live.client, bucket: live.bucket)]

    _ = try await Preprocessor(
      tools: Preprocessor.Tools(
        runner: SirilRunner.make(mode: .default, binary: binary, work: remoteWork))
    ).perform(request) { _ in }

    let localDigests = try Self.masterDigests(in: localOut)
    #expect(!localDigests.isEmpty, "the local run wrote masters")
    #expect(
      try Self.masterDigests(in: remoteOut) == localDigests,
      "same frames, same scripts, same masters — Siril does the pixel math")
    #expect(
      !FileManager.default.fileExists(atPath: remoteWork.appendingPathComponent("light_L").path),
      "the lane's downloads went with it")
  }
}
