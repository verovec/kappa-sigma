import AppKit
import AstroStackApp
import Foundation
import Metal
import ProjectKit
import RemoteKit
import SwiftUI
import Synchronization
import TestSupport
import Testing

/// The Export stage's targets and rows (card 0152): toggles, the resolved s3:// folder, badges,
/// Copy S3 URL and Resend, laid out in each language.
@MainActor
@Suite(
  "Export targets — on this Mac and/or S3, rows with their badges",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ExportTargetsTests {
  static func host(_ view: some View, _ language: String) -> NSSize {
    let host = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: language)).frame(width: 520))
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
  }

  @Test(
    "the form shows each target's destination; rows offer what their record allows",
    .scratchDirectory, arguments: ["en", "fr"])
  func testTargetsAndRows(_ language: String) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 500)
    let model = try ExportStageModelTests.s3Model(opened, fake: fake, local: true, s3: true)
    #expect(Self.host(ExportTargetsForm(model: model), language).height > 0)
    #expect(model.remoteFolder?.hasPrefix("s3://exports/astro/") == true)

    await model.export()
    let failed = try #require(model.exports.first)
    #expect(ExportRecordRow.canResend(failed))
    #expect(Self.host(ExportRecordRow(record: failed, model: model), language).height > 0)
    #expect(Self.host(ExportForm(model: model), language).height > 0, "the upload line laid out")

    let s3Only = ProjectExport(
      id: 99, stackID: failed.stackID, imageID: failed.imageID, headStepID: nil, folder: nil,
      settingsJSON: "{}", files: ["a.png"], remoteURL: "s3://b/k", remoteStatus: .done,
      createdAt: 0, updatedAt: 0)
    #expect(!ExportRecordRow.canResend(s3Only), "nothing kept here to resend from")
    #expect(Self.host(ExportRecordRow(record: s3Only, model: model), language).height > 0)

    model.local = false
    model.s3 = nil
    #expect(!model.canExport)
    #expect(Self.host(ExportTargetsForm(model: model), language).height > 0, "no destination line")
  }

  @Test("Copy S3 URL puts the record's s3:// folder on the pasteboard service", .scratchDirectory)
  func testCopyRemoteURL() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let copied = Mutex<[String]>([])
    var services = try ExportStageModelTests.services()
    services.copy = { text in copied.withLock { $0.append(text) } }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    let record = ProjectExport(
      id: 1, stackID: 1, imageID: 1, headStepID: nil, folder: nil, settingsJSON: "{}",
      files: [], remoteURL: "s3://b/k", remoteStatus: .done, createdAt: 0, updatedAt: 0)

    model.copyRemoteURL(record)

    #expect(copied.withLock { $0 } == ["s3://b/k"])
  }

  @Test(
    "a resend needs the form's S3 connection, and is refused while nothing is chosen",
    .scratchDirectory)
  func testResendNeedsConnection() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try ExportStageModelTests.s3Model(
      opened, fake: ExportS3Fake(), local: true, s3: false)
    let record = ProjectExport(
      id: 1, stackID: 1, imageID: 1, headStepID: nil, folder: "/tmp", settingsJSON: "{}",
      files: [], remoteURL: "s3://b/k", remoteStatus: .failed, createdAt: 0, updatedAt: 0)

    await model.resend(record)

    #expect(model.failure == .exportS3(.resendNeedsConnection))
  }
}
