import AstroStackApp
import CryptoKit
import Foundation
import ProcessKit
import ProjectKit
import RemoteKit
import Synchronization
import TestSupport
import Testing

/// A scripted S3 for the Export stage: HEAD answers `headStatus`, PUT `putStatus`; every PUT body
/// is kept by key.
final class ExportS3Fake: Sendable {
  private struct State {
    var head: Int
    var put: Int
    var bodies: [String: Data] = [:]
    var methods: [String] = []
    var deleted: [String] = []
    /// PUTs after this many succeed answer `put` (nil: every PUT does).
    var okPuts: Int?
    var puts = 0
    /// The next PUT throws a cancellation.
    var cancelPut = false
  }

  private let state: Mutex<State>

  init(head: Int = 404, put: Int = 200, okPuts: Int? = nil, cancelPut: Bool = false) {
    state = Mutex(State(head: head, put: put, okPuts: okPuts, cancelPut: cancelPut))
  }

  var deleted: [String] { state.withLock { $0.deleted } }

  var bodies: [String: Data] { state.withLock { $0.bodies } }
  var methods: [String] { state.withLock { $0.methods } }
  func answer(put: Int) { state.withLock { $0.put = put } }

  /// A client of this fake (path-style on 127.0.0.1, no backoff waits).
  func client() throws -> S3Client {
    let transport = HTTPTransport(
      send: { request in try self.answer(request) },
      download: { _, _, _ in HTTPResponse(status: 500) })
    return S3Client(
      endpoint: try S3Endpoint(
        url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
        addressing: .pathStyle),
      credentials: S3Credentials(accessKey: "AK", secretKey: "s"), transport: transport,
      sleep: { _ in })
  }

  private func answer(_ request: HTTPRequest) throws -> HTTPResponse {
    let key = String(request.url.path.dropFirst("/exports/".count))
    if request.method == "PUT", state.withLock({ $0.cancelPut }) { throw CancellationError() }
    return state.withLock { state in
      state.methods.append(request.method)
      switch request.method {
      case "HEAD":
        return HTTPResponse(
          status: state.head, headers: state.head == 200 ? ["content-length": "1"] : [:])
      case "DELETE":
        state.deleted.append(key)
        state.bodies[key] = nil
        return HTTPResponse(status: 204)
      case "PUT":
        state.puts += 1
        let failing = state.okPuts.map { state.puts > $0 } ?? (state.put != 200)
        guard !failing else {
          return HTTPResponse(
            status: state.put == 200 ? 500 : state.put,
            body: Data("<Error><Code>InternalError</Code><Message>boom</Message></Error>".utf8))
        }
        state.bodies[key] = request.body ?? Data()
        return HTTPResponse(status: 200, headers: ["etag": "\"e\""])
      default:
        return HTTPResponse(status: 400)
      }
    }
  }
}

extension ExportStageModelTests {
  nonisolated static let target = S3Target(
    connectionID: UUID(), bucket: "exports", prefix: "astro/")

  /// The stage over `fake` (S3 connection `target.connectionID`), on this Mac and/or on S3.
  static func s3Model(
    _ opened: StudioModelTests.Opened, fake: ExportS3Fake, local: Bool, s3: Bool,
    sources: [RemoteLocation] = []
  ) throws -> ExportStageModel {
    var services = try Self.services()
    let client = try fake.client()
    services.s3Client = { id in id == Self.target.connectionID ? client : nil }
    services.remoteSources = { sources }
    let model = try Self.model(opened, studio: try Self.separated(opened), services: services)
    model.settings.deliverables = [.final]
    model.local = local
    model.s3 = s3 ? Self.target : nil
    return model
  }

  static func sha(_ data: Data) -> String { Data(SHA256.hash(data: data)).base64EncodedString() }

  struct DestinationRow: Sendable, CustomTestStringConvertible {
    let local: Bool
    let s3: Bool
    var testDescription: String { "local \(local), S3 \(s3)" }
  }

  @Test(
    "testDestinations: on this Mac, on S3, both; the folder and s3:// URL shown are written",
    .scratchDirectory,
    arguments: [
      DestinationRow(local: true, s3: false), DestinationRow(local: false, s3: true),
      DestinationRow(local: true, s3: true),
    ])
  func testDestinations(row: DestinationRow) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(opened, fake: fake, local: row.local, s3: row.s3)
    let folder = try #require(model.folder)
    let remote = model.remoteFolder

    await model.export()

    #expect(model.failure == nil)
    let record = try #require(model.exports.first)
    #expect(record.folder == (row.local ? folder.path : nil))
    #expect(record.remoteURL == remote && (remote != nil) == row.s3)
    #expect(record.remoteStatus == (row.s3 ? .done : .none))
    let names = record.files
    #expect(
      names.allSatisfy {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
      }
        == row.local)
    let prefix = remote.map { String($0.dropFirst("s3://exports/".count)) + "/" } ?? ""
    #expect(Set(fake.bodies.keys) == (row.s3 ? Set(names.map { prefix + $0 }) : []))
    #expect(remote?.hasPrefix("s3://exports/astro/M31/run1/2026-10-22-120000") ?? !row.s3)
  }

  @Test("no destination at all is refused before anything is written", .scratchDirectory)
  func testDestinations_none() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: false)

    await model.export()

    #expect(model.failure == .exportS3(.noDestination))
    #expect(model.exports.isEmpty && fake.methods.isEmpty)
    #expect(!model.canExport)
  }

  @Test("both targets: S3 receives exactly the bytes written on this Mac", .scratchDirectory)
  func testBothTargetsUploadTheWrittenFiles() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)
    model.settings.formats = [.png16, .tiff16]

    await model.export()

    let folder = try #require(model.exports.first?.folder).map { URL(fileURLWithPath: $0) }
    let files = try #require(model.exports.first?.files)
    #expect(files.count == 2)
    for name in files {
      let local = try Data(contentsOf: try #require(folder).appendingPathComponent(name))
      let uploaded = try #require(fake.bodies.first { $0.key.hasSuffix("/" + name) }?.value)
      #expect(Self.sha(uploaded) == Self.sha(local), "\(name): same SHA-256 both sides")
    }
  }

  @Test(
    "S3 only: staged in the scratch folder, uploaded, staging removed, no folder recorded",
    .scratchDirectory)
  func testS3OnlyLeavesNoLocalFiles() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)

    await model.export()

    #expect(model.failure == nil && model.exports.first?.folder == nil)
    #expect(!fake.bodies.isEmpty && model.written.isEmpty)
    let scratch = try ScratchDirectory.url.appendingPathComponent("work")
    let staged = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
    #expect(staged.allSatisfy { !$0.hasPrefix("export_") }, "the staging folder is gone")
    #expect(!FileManager.default.fileExists(atPath: try Self.defaultBase().path))
  }

  @Test("an object already at the S3 path refuses the export, nothing written", .scratchDirectory)
  func testRemoteOverwriteRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(head: 200)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)
    let folder = try #require(model.folder)
    let remote = try #require(model.remoteFolder)

    await model.export()

    guard case .exportWouldOverwrite(let path) = model.failure else {
      Issue.record("expected exportWouldOverwrite, got \(String(describing: model.failure))")
      return
    }
    #expect(path.hasPrefix(remote + "/"))
    #expect(!fake.methods.contains("PUT") && model.exports.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test("a capture bucket/prefix is never an export target (R7 on remote)", .scratchDirectory)
  func testRemoteCaptureBucketRefusedByTheStage() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake()
    let model = try Self.s3Model(
      opened, fake: fake, local: true, s3: true,
      sources: [RemoteLocation(bucket: "exports", prefix: "astro")])

    await model.export()

    #expect(model.failure == .exportS3(.captureBucket(try #require(model.remoteFolder))))
    #expect(fake.methods.isEmpty && model.exports.isEmpty)
  }

  @Test(
    "local written + upload failed: recorded failed with S3's words, Resend makes it done",
    .scratchDirectory)
  func testUploadFailureRecordedAndResend() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 500)
    let model = try Self.s3Model(opened, fake: fake, local: true, s3: true)

    await model.export()

    let failed = try #require(model.exports.first)
    #expect(failed.remoteStatus == .failed && failed.folder != nil)
    #expect(failed.remoteError == "S3 500 InternalError: boom")
    #expect(model.failure == .exportS3(.uploadFailed("S3 500 InternalError: boom")))
    #expect(fake.bodies.isEmpty)

    fake.answer(put: 200)
    model.s3 = nil  // the row's own connection is used, never the form's
    await model.resend(failed)

    let resent = try #require(model.exports.first)
    #expect(resent.id == failed.id && resent.remoteStatus == .done && resent.remoteError == nil)
    #expect(Set(fake.bodies.keys.map { ($0 as NSString).lastPathComponent }) == Set(failed.files))
    #expect(model.failure == nil)
  }

  @Test(
    "S3 only + upload failed: nothing recorded, the error shown, nothing left", .scratchDirectory)
  func testS3OnlyFailureRecordsNothing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fake = ExportS3Fake(put: 403)
    let model = try Self.s3Model(opened, fake: fake, local: false, s3: true)

    await model.export()

    #expect(model.exports.isEmpty)
    #expect(model.failure == .exportS3(.service("S3 403 InternalError: boom")))
  }
}
