import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import TestSupport
import Testing

/// Card 0190: one plan for a project, whatever its nights are read from — folders of this Mac and
/// the bucket prefixes its sources record, scanned as one capture.
@Suite("ImportPlanning — folders and bucket nights planned as one capture")
struct ImportPlanningCaptureTests {
  static let connection = UUID()
  static let zone = TimeZone(identifier: "Europe/Paris") ?? .gmt

  /// Where one half of the capture is read from.
  enum Where: String, Sendable {
    case disk, bucket
  }

  /// The frames of a mono night: `lights/` (3 L lights) and `calib/` (3 darks), by relative path.
  static func night() -> [String: Data] {
    let common = [
      ("EXPTIME", "15.0"), ("GAIN", "100"), ("CCD-TEMP", "-20.0"), ("OBJECT", "'M42'"),
      ("FILTER", "'L'"), ("DATE-OBS", "'2026-09-15T03:00:00'"),
    ]
    var files: [String: Data] = [:]
    for index in 0..<3 {
      files["lights/l_\(index).fits"] = RemoteObjectStoreS3Tests.fits(
        [("IMAGETYP", "'Light Frame'")] + common)
      files["calib/DARK/d_\(index).fits"] = RemoteObjectStoreS3Tests.fits(
        [("IMAGETYP", "'Dark Frame'")] + common)
    }
    return files
  }

  /// A project whose capture is `night()`, each half on disk or in the bucket `astro` under
  /// `night/`, the bucket halves recorded as remote sources; the paths a run would plan.
  struct Capture {
    let project: ProjectPackage
    let paths: [String]
    let client: S3Client
  }

  static func capture(lights: Where, calib: Where, name: String) throws -> Capture {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(
      at: scratch.appendingPathComponent("\(name).astrostack"))
    var objects: [String: Data] = [:]
    var paths: [String] = []
    for (folder, place) in [("lights", lights), ("calib", calib)] {
      let files = night().filter { $0.key.hasPrefix(folder + "/") }
      switch place {
      case .disk:
        let root = scratch.appendingPathComponent("\(name)/\(folder)")
        for (path, data) in files {
          let url = scratch.appendingPathComponent("\(name)/\(path)")
          try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: url)
        }
        try project.store.addSource(kind: .night, path: root.path)
        paths.append(root.path)
      case .bucket:
        for (path, data) in files { objects["night/" + path] = data }
        let source = try project.store.addSource(
          remote: connection.uuidString, bucket: "astro", prefix: "night/" + folder)
        paths.append(source.path)
      }
    }
    return Capture(
      project: project, paths: paths, client: try RemoteObjectStoreS3Tests.client(objects))
  }

  static func plan(_ capture: Capture, client: ImportPlanning.Client? = nil) async throws
    -> ImportPlan
  {
    let store = capture.project.store
    let s3 = capture.client
    return try await ImportPlanning.plan(
      ImportRequest(paths: capture.paths), store: store,
      index: LibraryIndex(store: store, folder: try ScratchDirectory.url), timeZone: zone,
      client: client ?? { _ in s3 })
  }

  @Test(
    "testPlan_MergesLocalAndRemoteNights: one inventory, one root's darks for another's lights",
    .scratchDirectory,
    arguments: [
      (Where.disk, Where.disk), (Where.bucket, Where.bucket), (Where.disk, Where.bucket),
      (Where.bucket, Where.disk),
    ])
  func testPlan_MergesLocalAndRemoteNights(lights: Where, calib: Where) async throws {
    let capture = try Self.capture(
      lights: lights, calib: calib, name: "P-\(lights.rawValue)-\(calib.rawValue)")
    defer { try? capture.project.close() }

    let plan = try await Self.plan(capture)

    #expect(plan.inventory.frames.count { $0.type == .light } == 3)
    #expect(plan.inventory.frames.count { $0.type == .dark } == 3)
    let channel = try #require(plan.calibration.first)
    let dark = try #require(channel.cells.first { $0.role == .dark })
    #expect(dark.status == .build(frames: 3), "the darks of the other root: \(dark.status)")
    let remote = plan.inventory.frames.filter { $0.path.hasPrefix("s3://astro/night/") }
    let expected = (lights == .bucket ? 3 : 0) + (calib == .bucket ? 3 : 0)
    #expect(remote.count == expected, "bucket frames keep their virtual paths")
    #expect(Set(plan.identities.keys) == Set(remote.map(\.path)), "what the bucket answered")
    for path in capture.paths where path.hasPrefix("s3://") {
      #expect(try capture.project.store.remoteScan(of: path) != nil, "the reads are kept")
    }
  }

  @Test(
    "testPlan_RemoteFailure_FailsWholePlan: no plan of the local half alone",
    .scratchDirectory)
  func testPlan_RemoteFailure_FailsWholePlan() async throws {
    let capture = try Self.capture(lights: .disk, calib: .bucket, name: "F")
    defer { try? capture.project.close() }
    let refusing = S3Client(
      endpoint: capture.client.endpoint,
      credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: HTTPTransport(
        send: { _ in
          HTTPResponse(
            status: 403,
            body: Data(
              "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>".utf8))
        },
        download: { _, _, _ in HTTPResponse(status: 500) }))

    await #expect(throws: S3Error.self) {
      _ = try await Self.plan(capture, client: { _ in refusing })
    }
    await #expect(throws: RemoteImportProblem.connectionMissing) {
      _ = try await Self.plan(capture, client: { _ in nil })
    }
  }

  @Test(
    "a bucket path the project records no source for is refused, named as a lost connection",
    .scratchDirectory)
  func testPlan_UnrecordedPrefix_Refused() async throws {
    let capture = try Self.capture(lights: .disk, calib: .disk, name: "U")
    defer { try? capture.project.close() }
    let store = capture.project.store
    let s3 = capture.client

    await #expect(throws: RemoteImportProblem.connectionMissing) {
      _ = try await ImportPlanning.plan(
        ImportRequest(paths: capture.paths + ["s3://astro/elsewhere"]), store: store,
        index: LibraryIndex(store: store, folder: try ScratchDirectory.url), timeZone: Self.zone,
        client: { _ in s3 })
    }
  }
}
