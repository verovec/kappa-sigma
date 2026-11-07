import AstroStackApp
import Foundation
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// Card 0185: an export never replaces an object, even one its key cannot see — the service is
/// asked (`If-None-Match: *`) and its refusal reads as the overwrite it would have been. Resend
/// replaces what the failed copy left: that is its purpose.
extension ExportStageModelTests {
  @Test(
    "a key that can read: checked first, the service asked as well, nothing said",
    .scratchDirectory)
  func testCheckedKeyAsksTheServiceToo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(head: 404)
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)

    await model.export()

    #expect(model.failure == nil && !model.remoteUnchecked)
    #expect(!fake.conditions.isEmpty && fake.conditions.allSatisfy { $0 == "*" })
  }

  struct OverwriteRow: Sendable, CustomTestStringConvertible {
    let local: Bool
    var testDescription: String { local ? "on this Mac and S3" : "S3 only" }
  }

  @Test(
    "the service refuses an overwrite (412): said as the object that already exists",
    .scratchDirectory, arguments: [OverwriteRow(local: false), OverwriteRow(local: true)])
  func testServiceRefusedOverwrite(row: OverwriteRow) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(head: 403, put: 412)
    let model = try Self.s3Model(opened, fake: fake, local: row.local, s3: true)
    let folder = try #require(model.remoteFolder)

    await model.export()

    let shown = String(localized: try #require(model.failure).message)
    #expect(shown.contains(folder) && shown.contains("already exists"), "\(shown)")
    #expect(fake.bodies.isEmpty)
    if row.local {
      let failed = try #require(model.exports.first)
      #expect(failed.remoteStatus == .failed && failed.remoteError?.contains(folder) == true)
    } else {
      #expect(model.exports.isEmpty, "S3 only: nothing recorded, nothing left")
    }
  }

  @Test("Resend replaces what the failed copy left: no condition on its PUTs", .scratchDirectory)
  func testResendReplaces() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 500)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)
    await model.export()
    let failed = try #require(model.exports.first)
    let sentByExport = fake.conditions.count
    fake.answer(put: 200)

    await model.resend(failed)

    let resent = fake.conditions.dropFirst(sentByExport)
    #expect(!resent.isEmpty && resent.allSatisfy { $0 == nil })
    #expect(model.exports.first?.remoteStatus == .done)
  }
}
