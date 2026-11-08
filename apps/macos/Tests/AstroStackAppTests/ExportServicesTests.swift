import AppKit
import AstroStackApp
import Foundation
import ProcessKit
import ProjectKit
import TestSupport
import Testing

@MainActor
@Suite("ExportServices: what the Export stage reaches outside the project")
struct ExportServicesTests {
  /// A project document named `name` in the scratch folder, its window open unless `window` is
  /// false, holding `remote` nights (one connection each) and, when `night`, a local night too.
  static func project(
    _ name: String, remote: [RemoteLocation], night: Bool = false, window: Bool = true
  ) throws -> ProjectDocument {
    let url = try ScratchDirectory.url.appendingPathComponent("\(name).astrostack")
    let package = try ProjectPackage.create(at: url)
    for location in remote {
      _ = try package.store.addSource(
        remote: UUID().uuidString, bucket: location.bucket, prefix: location.prefix)
    }
    if night { _ = try package.store.addSource(kind: .night, path: try ScratchDirectory.url.path) }
    try package.close()
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectPackage.typeIdentifier)
    if window { document.makeWindowControllers() }
    return document
  }

  @Test(
    "the app's services: every open project's remote nights, from its database, window or not",
    .scratchDirectory)
  func testAppServices_remoteSourcesAreEveryOpenProjectsRemoteNights() throws {
    let first = try Self.project(
      "M31",
      remote: [
        RemoteLocation(bucket: "astro", prefix: "M31/n1"),
        RemoteLocation(bucket: "astro", prefix: ""),
      ])
    let second = try Self.project(
      "IC1848", remote: [RemoteLocation(bucket: "other", prefix: "IC/a")], night: true)
    let windowless = try Self.project(
      "NGC7000", remote: [RemoteLocation(bucket: "astro", prefix: "NGC7000")], window: false)
    let untitled = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    let other = NSDocument()
    defer { for document in [first, second, windowless, untitled, other] { document.close() } }
    // Synchronous on the main actor: no other test sees the stub before it is restored.
    let documents = ProjectDocument.openDocuments
    defer { ProjectDocument.openDocuments = documents }
    ProjectDocument.openDocuments = { [first, untitled, other, second, windowless] }

    let sources = ExportServices.live.remoteSources()

    #expect(
      sources == [
        RemoteLocation(bucket: "astro", prefix: "M31/n1"),
        RemoteLocation(bucket: "astro", prefix: ""),
        RemoteLocation(bucket: "other", prefix: "IC/a"),
        RemoteLocation(bucket: "astro", prefix: "NGC7000"),
      ])
  }

  struct SourceRow: Sendable, CustomTestStringConvertible {
    let name: String
    let kind: ProjectSource.Kind
    let bucket: String?
    let prefix: String?
    var path = "s3://astro/M31"
    let location: RemoteLocation?
    var testDescription: String { name }
  }

  @Test(
    "a remote night is its bucket and prefix; a local row, or one missing either, is none",
    arguments: [
      SourceRow(
        name: "remote", kind: .remoteNight, bucket: "astro", prefix: "M31",
        location: RemoteLocation(bucket: "astro", prefix: "M31")),
      SourceRow(
        name: "whole bucket", kind: .remoteNight, bucket: "astro", prefix: "",
        location: RemoteLocation(bucket: "astro", prefix: "")),
      SourceRow(
        name: "no bucket column: the path", kind: .remoteNight, bucket: nil, prefix: "M31",
        location: RemoteLocation(bucket: "astro", prefix: "M31")),
      SourceRow(
        name: "no columns, a whole bucket's path", kind: .remoteNight, bucket: nil, prefix: nil,
        path: "s3://astro", location: RemoteLocation(bucket: "astro", prefix: "")),
      SourceRow(
        name: "no columns, no s3:// path", kind: .remoteNight, bucket: nil, prefix: nil,
        path: "/Volumes/astro/M31", location: nil),
      SourceRow(name: "local night", kind: .night, bucket: "astro", prefix: "M31", location: nil),
    ])
  func testRemoteLocation_fromSource(row: SourceRow) {
    let source = ProjectSource(
      id: 1, kind: row.kind, path: row.path, readOnly: true, bucket: row.bucket,
      prefix: row.prefix, createdAt: 0, updatedAt: 0)

    #expect(RemoteLocation(source: source) == row.location)
  }
}
