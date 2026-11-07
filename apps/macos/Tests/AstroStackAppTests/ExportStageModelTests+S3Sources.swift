import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

extension ExportStageModelTests {
  struct OtherProjectRow: Sendable, CustomTestStringConvertible {
    let prefix: String
    let refused: Bool
    var testDescription: String { "\(prefix) → \(refused ? "refused" : "allowed")" }
  }

  /// The stage over `fake`, exporting to S3 only under `prefix`, its capture sources `sources`
  /// read at each check as the app's are.
  static func s3Model(
    _ opened: StudioModelTests.Opened, fake: ExportS3Fake, local: Bool, prefix: String,
    sources: @escaping @MainActor @Sendable () -> [RemoteLocation]
  ) throws -> ExportStageModel {
    var services = try Self.services()
    let client = try fake.client()
    services.s3Client = { id in id == Self.target.connectionID ? client : nil }
    services.remoteSources = sources
    let model = try Self.model(opened, studio: try Self.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.local = local
    model.s3 = S3Target(
      connectionID: Self.target.connectionID, bucket: Self.target.bucket, prefix: prefix)
    return model
  }

  /// R7 on remote reaches past the exporting project: another open window's capture prefix is
  /// refused too, folder by folder.
  @Test(
    "a prefix another open project imports captures from is never an export target",
    .scratchDirectory,
    arguments: [
      OtherProjectRow(prefix: "a/b", refused: true),
      OtherProjectRow(prefix: "a/b/c", refused: true),
      OtherProjectRow(prefix: "a/b-c", refused: false),
    ])
  func testCaptureBucketOfAnotherOpenProjectRefused(row: OtherProjectRow) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let other = try ExportServicesTests.project(
      "Other", remote: [RemoteLocation(bucket: Self.target.bucket, prefix: "a/b")])
    defer { other.close() }
    let fake = ExportS3Fake()
    // What `live` reads, over the other project only: nothing global is stubbed across `await`.
    let model = try Self.s3Model(
      opened, fake: fake, local: false, prefix: row.prefix,
      sources: { ProjectDocument.remoteLocations(of: [other]) })

    await model.export()

    if row.refused {
      #expect(model.failure == .exportS3(.captureBucket(try #require(model.remoteFolder))))
      #expect(fake.methods.isEmpty && model.exports.isEmpty)
    } else {
      #expect(model.failure == nil)
      #expect(fake.methods.contains("PUT") && model.exports.count == 1)
    }
  }

  @Test(
    "a prefix that becomes a capture source while the files are written is refused before any PUT",
    .scratchDirectory)
  func testCapturePrefixImportedDuringTheExportRefusedBeforeUpload() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    // The plan's check sees no capture; the one before the upload sees the prefix imported.
    let checks = CheckCount()
    let model = try Self.s3Model(
      opened, fake: fake, local: true, prefix: "a/b",
      sources: {
        checks.count += 1
        return checks.count == 1 ? [] : [RemoteLocation(bucket: "exports", prefix: "a")]
      })

    await model.export()

    let record = try #require(model.exports.first)
    #expect(record.remoteStatus == .failed && record.folder != nil)
    #expect(!fake.methods.contains("PUT"))
    // The record's own URL: after an export the stage's folder names the next one's time.
    let url = try #require(record.remoteURL)
    #expect(record.remoteError?.contains(url) == true)
  }
}

/// How many times the stage asked for the capture sources.
@MainActor
final class CheckCount {
  var count = 0
}
