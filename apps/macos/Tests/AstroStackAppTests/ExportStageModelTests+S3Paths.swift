import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import SwiftUI
import TestSupport
import Testing

extension ExportStageModelTests {
  @Test(
    "S3 refusals before any write: no bucket, unknown connection, an unreadable answer",
    .scratchDirectory)
  func testRemoteRefusals() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(head: 500)
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)

    model.s3?.bucket = "  "
    await model.export()
    #expect(model.failure == .exportS3(.noBucket))

    model.s3 = S3Target(connectionID: UUID(), bucket: "exports", prefix: "")
    await model.export()
    #expect(model.failure == .exportS3(.connectionMissing))

    model.s3 = Self.target
    await model.export()
    guard case .exportS3(.service(let text)) = model.failure else {
      Issue.record("expected the service's words, got \(String(describing: model.failure))")
      return
    }
    #expect(text.hasPrefix("S3 500"))
    #expect(model.exports.isEmpty && !fake.methods.contains("PUT"))
  }

  @Test(
    "S3 only with a template that names no folder is refused with the template's reason",
    .scratchDirectory)
  func testRemoteTemplateRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.s3Model(opened, fake: ExportS3Fake(), local: false, s3: true)
    model.template = "{nope}"

    await model.export()

    guard case .exportTemplate = model.failure else {
      Issue.record("expected the template's refusal, got \(String(describing: model.failure))")
      return
    }
    #expect(model.remoteFolder == nil)
  }

  @Test(
    "Resend: nothing kept here does nothing; a gone connection or a new failure says so",
    .scratchDirectory)
  func testResendPaths() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 500)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)
    await model.export()
    let failed = try #require(model.exports.first)

    let s3Only = ProjectExport(
      id: failed.id, stackID: failed.stackID, imageID: failed.imageID, headStepID: nil,
      folder: nil, settingsJSON: "{}", files: failed.files, remoteURL: failed.remoteURL,
      remoteStatus: .failed, remoteConnection: failed.remoteConnection, createdAt: 0,
      updatedAt: 0)
    await model.resend(s3Only)
    #expect(fake.methods.filter { $0 == "PUT" }.count == 3, "no folder: nothing resent")

    let elsewhere = ProjectExport(
      id: failed.id, stackID: failed.stackID, imageID: failed.imageID, headStepID: nil,
      folder: failed.folder, settingsJSON: "{}", files: failed.files,
      remoteURL: failed.remoteURL, remoteStatus: .failed,
      remoteConnection: UUID().uuidString, createdAt: 0, updatedAt: 0)
    await model.resend(elsewhere)
    #expect(model.failure == .exportS3(.connectionMissing))

    await model.resend(failed)
    #expect(model.exports.first?.remoteStatus == .failed)
    #expect(model.failure == .exportS3(.uploadFailed("S3 500 InternalError: boom")))

    fake.answer(put: 200)
    await model.startResend(failed)?.value
    #expect(model.exports.first?.remoteStatus == .done)
  }

  @Test("a cancelled resend keeps the row failed, resendable", .scratchDirectory)
  func testResendCancelled() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.s3Model(opened, fake: ExportS3Fake(put: 500), local: true, s3: true)
    await model.export()
    let failed = try #require(model.exports.first)
    let cancelling = ExportS3Fake(cancelPut: true)
    let client = try cancelling.client()
    var services = try Self.services()
    services.s3Client = { _ in client }
    let other = try Self.model(opened, studio: model.studio, services: services)

    await other.resend(failed)

    let row = try #require(other.exports.first)
    #expect(row.remoteStatus == .failed && ExportRecordRow.canResend(row))
  }

  @Test(
    "an export started as a task can be cancelled; the form lays out with connections",
    .scratchDirectory, arguments: ["en", "fr"])
  func testStartAndCancelExport(_ language: String) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var services = try Self.services()
    let fake = ExportS3Fake()
    let client = try fake.client()
    services.s3Client = { _ in client }
    services.s3Connections = {
      [
        S3Connection(
          id: Self.target.connectionID, name: "Exports", endpoint: "http://127.0.0.1:9000",
          region: "", pathStyle: true, accessKey: "AK")
      ]
    }
    let model = try Self.model(opened, studio: try Self.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.local = false
    model.s3 = Self.target
    let host = NSHostingView(
      rootView: ExportForm(model: model).environment(\.locale, Locale(identifier: language))
        .frame(width: 520))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 0 && model.s3Connections.count == 1)

    let task = try #require(model.startExport())
    #expect(model.startExport() == nil, "one export at a time")
    model.cancelExport()
    await task.value
    #expect(!model.isExporting)
    let again = model.startExport()
    #expect(again != nil, "idle again once it ended")
    model.cancelExport()
    await again?.value
  }

  @Test("s3:// URLs split into bucket and key; files get the type a browser needs")
  func testURLHelpers() throws {
    #expect(try #require(ExportStageModel.split("s3://b/k/l")) == ("b", "k/l"))
    #expect(try #require(ExportStageModel.split("s3://b")) == ("b", ""))
    #expect(ExportStageModel.split("https://b/k") == nil)
    #expect(ExportStageModel.split("s3:///k") == nil)
    let types = ["png", "tif", "TIFF", "jpg", "fits", "xyz"].map {
      ExportStageModel.contentType(URL(fileURLWithPath: "/a.\($0)"))
    }
    #expect(
      types == [
        "image/png", "image/tiff", "image/tiff", "image/jpeg", "application/fits",
        "application/octet-stream",
      ])
  }

  @Test("the live client of a connection Settings does not hold is nil")
  func testLiveClientUnknownConnection() throws {
    #expect(try ExportServices.liveClient(UUID()) == nil)
  }
}
