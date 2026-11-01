import AstroStackApp
import CryptoKit
import Foundation
import Metal
import RemoteKit
import TestSupport
import Testing

/// The Export stage against a real S3: a local `minio server` named by
/// `ASTROSTACK_S3_LIVE_ENDPOINT` (`just s3-live` documents it), never a real bucket by default.
enum LiveExportS3 {
  /// The client of the live endpoint (minioadmin keys unless given), `nil` to skip.
  static var client: S3Client? {
    let env = ProcessInfo.processInfo.environment
    guard env["ASTROSTACK_SKIP_LIVE"] != "1", let text = env["ASTROSTACK_S3_LIVE_ENDPOINT"],
      let url = URL(string: text),
      let endpoint = try? S3Endpoint(url: url, region: "us-east-1", addressing: .pathStyle)
    else { return nil }
    return S3Client(
      endpoint: endpoint,
      credentials: S3Credentials(
        accessKey: env["ASTROSTACK_S3_LIVE_ACCESS_KEY"] ?? "minioadmin",
        secretKey: env["ASTROSTACK_S3_LIVE_SECRET_KEY"] ?? "minioadmin"),
      transport: .urlSession())
  }

  /// Creates the live bucket (« already owned » is fine), as `LiveS3Tests` does.
  static func ensureBucket() async throws {
    let env = ProcessInfo.processInfo.environment
    let url = try #require(URL(string: env["ASTROSTACK_S3_LIVE_ENDPOINT"] ?? ""))
    let endpoint = try S3Endpoint(url: url, region: "us-east-1", addressing: .pathStyle)
    let credentials = S3Credentials(
      accessKey: env["ASTROSTACK_S3_LIVE_ACCESS_KEY"] ?? "minioadmin",
      secretKey: env["ASTROSTACK_S3_LIVE_SECRET_KEY"] ?? "minioadmin")
    let request = try S3Request(method: "PUT", bucket: bucket, key: "").prepared(
      endpoint: endpoint, signer: SigV4(credentials: credentials, region: "us-east-1"),
      date: Date())
    let response = try await HTTPTransport.urlSession().send(request)
    #expect(response.isSuccess || response.status == 409, "create bucket: \(response.status)")
  }

  /// The bucket the test writes under a random prefix of.
  static let bucket =
    ProcessInfo.processInfo.environment["ASTROSTACK_S3_LIVE_BUCKET"]
    ?? "astrostack-live"
}

@MainActor
@Suite(
  "Live export to S3: the files written here and their S3 copies are the same bytes",
  .enabled(if: LiveExportS3.client != nil, "ASTROSTACK_S3_LIVE_ENDPOINT unset (just s3-live)"),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"),
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveExportS3Tests {
  @Test(
    "export on this Mac and to MinIO: each object's SHA-256 = the local file's", .scratchDirectory)
  func testExportBothToMinIO() async throws {
    let client = try #require(LiveExportS3.client)
    try await LiveExportS3.ensureBucket()
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let target = S3Target(
      connectionID: UUID(), bucket: LiveExportS3.bucket,
      prefix: "astrostack-live/\(UUID().uuidString)")
    var services = try ExportStageModelTests.services()
    services.s3Client = { _ in client }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.settings.formats = [.png16, .tiff16]
    model.s3 = target

    await model.export()

    #expect(model.failure == nil)
    let record = try #require(model.exports.first)
    let folder = URL(fileURLWithPath: try #require(record.folder))
    let key = String(try #require(record.remoteURL).dropFirst("s3://\(target.bucket)/".count))
    for name in record.files {
      let local = try Data(contentsOf: folder.appendingPathComponent(name))
      let remote = try await client.get(bucket: target.bucket, key: "\(key)/\(name)", range: nil)
      #expect(SHA256.hash(data: remote) == SHA256.hash(data: local), "\(name)")
      try await client.delete(bucket: target.bucket, key: "\(key)/\(name)")
    }
  }
}
