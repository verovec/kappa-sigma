import AstroStackApp
import Foundation
import ProcessKit
import ProjectKit
import TestSupport
import Testing

extension ExportStageModelTests {
  @Test(
    "a write-only key (HEAD 403) still exports: said on the stage, the service never replaces",
    .scratchDirectory)
  func testWriteOnlyKeyProceeds() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(head: 403)
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)

    await model.export()

    #expect(model.failure == nil && model.exports.first?.remoteStatus == .done)
    #expect(!fake.bodies.isEmpty)
    #expect(model.remoteUnchecked, "what the key could not check is said (card 0185)")
    #expect(!fake.conditions.isEmpty && fake.conditions.allSatisfy { $0 == "*" })
  }

  @Test(
    "S3 only, second file refused: the first object is deleted, nothing recorded",
    .scratchDirectory)
  func testS3OnlyPartialFailureLeavesNothing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 403, okPuts: 1)
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)
    model.settings.formats = [.png16, .tiff16]

    await model.export()

    #expect(model.exports.isEmpty)
    #expect(fake.deleted.count == 1 && fake.bodies.isEmpty, "the object already sent is gone")
    guard case .exportS3(.service) = model.failure else {
      Issue.record("expected the service's refusal, got \(String(describing: model.failure))")
      return
    }
  }

  @Test(
    "a cancelled copy: S3 only records nothing; with local files the row is resendable",
    .scratchDirectory, arguments: [false, true])
  func testCancelledUpload(local: Bool) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(cancelPut: true)
    let model = try Self.s3Model(opened, fake: fake, local: local, s3: true)

    await model.export()

    if local {
      let row = try #require(model.exports.first)
      #expect(row.remoteStatus == .failed && row.remoteError?.isEmpty == false)
      #expect(row.remoteConnection == Self.target.connectionID.uuidString)
      #expect(model.failure == nil, "the user's own cancel: no failure banner")
    } else {
      #expect(model.exports.isEmpty && model.failure == nil, "a cancel is not a failure")
    }
  }

  @Test("a pasted bucket with spaces is trimmed: shown = requested = recorded", .scratchDirectory)
  func testBucketTrimmed() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)
    model.s3?.bucket = " exports \n"
    let shown = try #require(model.remoteFolder)

    await model.export()

    #expect(shown.hasPrefix("s3://exports/"))
    #expect(model.exports.first?.remoteURL == shown && !fake.bodies.isEmpty)
  }

  @Test(
    "« Remember as default » applies even when the S3 copy failed after the local write",
    .scratchDirectory)
  func testRememberedDespiteFailedUpload() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let suite = "fr.astrostack.tests.exportstage.\(UUID().uuidString)"
    let fake = ExportS3Fake(put: 500)
    var services = try Self.services(suite: suite)
    let client = try fake.client()
    services.s3Client = { _ in client }
    let model = try Self.model(opened, studio: try Self.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.s3 = Self.target
    model.remember = true

    await model.export()

    #expect(model.exports.first?.remoteStatus == .failed)
    #expect(services.destination.s3 == Self.target && services.destination.local)
  }

  @Test(
    "a cancel during the S3 checks stops quietly: no refusal shown, nothing written",
    .scratchDirectory)
  func testCancelDuringChecks() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(cancelHead: true)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)

    await model.export()

    #expect(model.failure == nil && model.exports.isEmpty && !fake.methods.contains("PUT"))
  }

  @Test(
    "S3 only + Remember: the S3 target is kept even when the local base is unusable",
    .scratchDirectory)
  func testRememberS3OnlyIgnoresTheBase() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let suite = "fr.astrostack.tests.exportstage.\(UUID().uuidString)"
    var services = try Self.services(suite: suite)
    let client = try ExportS3Fake().client()
    services.s3Client = { _ in client }
    let model = try Self.model(opened, studio: try Self.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.base = try ScratchDirectory.url.appendingPathComponent("unplugged")
    model.local = false
    model.s3 = S3Target(connectionID: Self.target.connectionID, bucket: " exports ", prefix: "a")
    model.remember = true

    await model.export()

    #expect(model.failure == nil)
    #expect(!services.destination.local)
    #expect(services.destination.s3?.bucket == "exports", "remembered trimmed")
  }

  @Test(
    "Resend judges R7 again: a prefix that became a capture source is refused",
    .scratchDirectory)
  func testResendRefusesCapturePrefix() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 500)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)
    await model.export()
    let failed = try #require(model.exports.first)
    var services = try Self.services()
    let client = try fake.client()
    services.s3Client = { _ in client }
    services.remoteSources = { [RemoteLocation(bucket: "exports", prefix: "astro")] }
    let later = try Self.model(opened, studio: model.studio, services: services)
    fake.answer(put: 200)

    await later.resend(failed)

    #expect(later.failure == .exportS3(.captureBucket(try #require(failed.remoteURL))))
    #expect(fake.bodies.isEmpty)
  }
}
