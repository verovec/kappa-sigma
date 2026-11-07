import AstroStackApp
import CryptoKit
import Foundation
import Metal
import RemoteKit
import TestSupport
import Testing

/// The Export stage against a real S3 service: the local MinIO `just s3-live` starts, or the bucket
/// `.env` names (`LiveS3Environment`), under a prefix of this test alone, removed at the end.
@MainActor
@Suite(
  "Live export to S3: the files written here and their S3 copies are the same bytes",
  .liveS3,
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"),
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveExportS3Tests {
  @Test(
    "export on this Mac and to MinIO: each object's SHA-256 = the local file's", .scratchDirectory)
  func testExportBothToMinIO() async throws {
    let live = try #require(LiveS3Environment.current)
    let client = live.client()
    try await live.ensureBucket(client)
    try await live.sweepOnce(client: client)
    let prefix = LiveS3Environment.runPrefix()
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let target = S3Target(
      connectionID: UUID(), bucket: live.bucket, prefix: String(prefix.dropLast()))
    var services = try ExportStageModelTests.services()
    services.s3Client = { _ in client }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.settings.formats = [.png16, .tiff16]
    model.s3 = target

    await model.export()

    do {
      #expect(model.failure == nil)
      let record = try #require(model.exports.first)
      let folder = URL(fileURLWithPath: try #require(record.folder))
      let key = String(try #require(record.remoteURL).dropFirst("s3://\(target.bucket)/".count))
      for name in record.files {
        let local = try Data(contentsOf: folder.appendingPathComponent(name))
        let remote = try await client.get(bucket: target.bucket, key: "\(key)/\(name)", range: nil)
        #expect(SHA256.hash(data: remote) == SHA256.hash(data: local), "\(name)")
      }
    } catch {
      Issue.record(error)
    }
    try await live.removePrefix(prefix, client: client)
  }
}
