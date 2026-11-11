import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0169: a bucket prefix added to the project is recorded as the remote source it is — with
/// the connection it is read through — never as a file path the scheme would be mangled into.
@MainActor
@Suite("ProjectWindowModel — a bucket prefix recorded as a remote source")
struct ProjectWindowModelBucketTests {
  static let connection = S3Connection(
    name: "Captures", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
    accessKey: "AK")

  static func window(_ project: ProjectPackage) -> ProjectWindowModel {
    ProjectWindowModel(
      store: { project.store },
      services: { _ in
        ImportServices(
          planning: ImportViewModel.reporting(ImportPlanningStub.empty),
          remotePlanning: { _, request, _ in
            ImportPlan(
              inventory: Inventory(root: request.paths.first ?? "", frames: []), library: [],
              request: request)
          },
          browsing: { _, _, _ in ["M31/2026-10-18/"] })
      })
  }

  @Test("the source is a remote night with its bucket, prefix and connection", .scratchDirectory)
  func testAddRecordsARemoteNight() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)

    window.startImport()
    let sheet = try #require(window.importing)
    let bucket = try #require(sheet.bucket)
    bucket.connectionID = Self.connection.id
    bucket.bucket = "astro"
    bucket.enter("M31/2026-10-18/")
    sheet.choose(bucket: try #require(bucket.target))
    await sheet.settled()
    window.add(sheet.request)

    let source = try #require(window.sources.first)
    #expect(window.sources.count == 1 && window.importing == nil)
    #expect(source.kind == .remoteNight, "not a night of this Mac")
    #expect(source.path == "s3://astro/M31/2026-10-18", "the scheme survives")
    #expect(source.bucket == "astro" && source.prefix == "M31/2026-10-18")
    #expect(source.connectionID == Self.connection.id.uuidString)
    #expect(source.readOnly && window.error == nil)
  }

  @Test("a folder import still records a night of this Mac", .scratchDirectory)
  func testAddStillRecordsLocalNights() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)

    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await sheet.settled()
    window.add(sheet.request)

    #expect(window.sources.map(\.kind) == [.night])
    #expect(window.sources.map(\.path) == ["/c/M31-DB"])
    #expect(window.sources.first?.bucket == nil)
  }

  @Test(
    "a bucket added to a project with no local night keeps the count the sheet measured",
    .scratchDirectory)
  func testAddKeepsTheSheetsCount() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store },
      services: { _ in
        ImportServices(
          planning: ImportViewModel.reporting(ImportPlanningStub.empty),
          remotePlanning: { _, request, _ in
            var frame = CaptureFrame(path: "s3://astro/M31/2026-10-18/l_1.fits")
            frame.type = .light
            frame.session = "2026-10-18"
            return ImportPlan(
              inventory: Inventory(root: request.paths.first ?? "", frames: [frame]),
              library: [], request: request)
          },
          browsing: { _, _, _ in [] })
      })

    window.startImport()
    let sheet = try #require(window.importing)
    let bucket = try #require(sheet.bucket)
    bucket.connectionID = Self.connection.id
    bucket.bucket = "astro"
    bucket.enter("M31/2026-10-18/")
    sheet.choose(bucket: try #require(bucket.target))
    await sheet.settled()
    window.add(sheet.request)
    await window.scanSettled()

    // The prefix is the project's only night: no rescan follows the Add, and the row keeps the
    // count the sheet read (card 0190: the sheet's plan is the project's scan too).
    let state = try #require(window.remoteState(of: "s3://astro/M31/2026-10-18"))
    #expect(state.lights == 1 && state.failure == nil)
  }
}
