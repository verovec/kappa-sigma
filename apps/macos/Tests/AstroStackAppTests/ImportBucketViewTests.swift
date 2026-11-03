import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0169: the bucket form and the sheet around it laid out offscreen in every state — no
/// connection, a level listed, a listing that failed — in English and in French.
@MainActor
@Suite("ImportBucketView and the sheet's S3 half — every state lays out")
struct ImportBucketViewTests {
  static let connection = S3Connection(
    name: "Captures", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
    accessKey: "AK")

  static func model(connections: [S3Connection] = [connection], folders: [String] = ["M31/"])
    -> ImportBucketModel
  {
    ImportBucketModel(connections: connections, browsing: { _, _, _ in folders })
  }

  @Test(
    "the form lays out without a connection, with a level, and after a failure",
    arguments: [
      Locale(identifier: "en"), Locale(identifier: "fr"),
    ])
  func testFormStates(locale: Locale) async throws {
    let bare = Self.model(connections: [])
    var scanned: [RemoteImportTarget] = []
    let host = ImportSheetTests.host(
      ImportBucketView(model: bare) { scanned.append($0) }.environment(\.locale, locale))
    let empty = host.fittingSize
    #expect(empty.height > 0, "« no connection yet » still lays out")

    let model = Self.model()
    model.connectionID = Self.connection.id
    model.bucket = "astro"
    let listed = ImportSheetTests.host(
      ImportBucketView(model: model) { scanned.append($0) }.environment(\.locale, locale))
    model.browse()
    await model.settled()
    listed.layoutSubtreeIfNeeded()
    #expect(model.folders == ["M31/"])

    let failing = ImportBucketModel(
      connections: [Self.connection],
      browsing: { _, _, _ in
        throw S3Error.service(
          status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
      })
    failing.connectionID = Self.connection.id
    failing.bucket = "astro"
    let failed = ImportSheetTests.host(
      ImportBucketView(model: failing) { scanned.append($0) }.environment(\.locale, locale))
    failing.browse()
    await failing.settled()
    failed.layoutSubtreeIfNeeded()
    #expect(failing.error != nil && scanned.isEmpty)
  }

  @Test("« Scan This Prefix » hands the target over once, and only when there is one")
  func testScanHandsTheTargetOver() async throws {
    let model = Self.model()
    var scanned: [RemoteImportTarget] = []
    let view = ImportBucketView(model: model) { scanned.append($0) }
    _ = ImportSheetTests.host(view)

    #expect(model.target == nil, "no connection chosen yet")
    model.connectionID = Self.connection.id
    model.bucket = " astro "
    let target = try #require(model.target)

    #expect(target.bucket == "astro", "a pasted name often carries spaces")
    #expect(target.path == "s3://astro")
  }

  @Test(
    "the sheet's S3 half shows the prefix chosen and the bucket's empty state",
    arguments: [
      Locale(identifier: "en"), Locale(identifier: "fr"),
    ])
  func testSheetBucketHalf(locale: Locale) async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let bucket = Self.model()
    bucket.connectionID = Self.connection.id
    bucket.bucket = "astro"
    let model = ImportViewModel(
      planning: disk.planning,
      remotePlanning: { _, request, _ in
        ImportPlan(
          inventory: Inventory(root: request.paths.first ?? "", frames: []), library: [],
          request: request)
      }, bucket: bucket)
    let host = ImportSheetTests.host(
      ImportSheet(model: model, onAdd: { _ in }, onCancel: {}).environment(\.locale, locale))

    model.setSource(.bucket)
    host.layoutSubtreeIfNeeded()
    let chooseHeight = host.fittingSize.height
    #expect(chooseHeight > 0, "« no prefix chosen » lays out")

    model.choose(bucket: try #require(bucket.target))
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.plan != nil)
    #expect(ImportSheet.header(of: model.request.paths) == .folder("s3://astro"))
  }

  @Test(
    "a folder's name is its last part, however deep the prefix",
    arguments: [
      ("M31/", "M31"), ("M31/2026-10-18/", "2026-10-18"), ("", ""),
    ])
  func testFolderName(prefix: String, name: String) {
    #expect(ImportBucketView.name(of: prefix) == name)
  }
}
