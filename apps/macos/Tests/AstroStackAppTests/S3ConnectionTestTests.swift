import AstroStackApp
import Foundation
import RemoteKit
import Synchronization
import Testing

/// Settings › S3 connections › Test (card 0150): one listing, the answer shown as is.
@MainActor
@Suite("S3 connection test — OK with a count, or the S3 error verbatim")
struct S3ConnectionTestTests {
  static let listing =
    "<ListBucketResult><IsTruncated>false</IsTruncated>"
    + "<Contents><Key>M31/a.fits</Key><Size>1</Size><ETag>e</ETag></Contents>"
    + "<Contents><Key>M31/b.fits</Key><Size>2</Size><ETag>e</ETag></Contents></ListBucketResult>"

  /// The URLs the fake transport was sent.
  final class Seen: Sendable {
    private let urls = Mutex<[URL]>([])
    func append(_ url: URL) { urls.withLock { $0.append(url) } }
    var all: [URL] { urls.withLock { $0 } }
  }

  static let denied =
    "<Error><Code>AccessDenied</Code><Message>Access Denied.</Message></Error>"

  /// A model over fresh defaults, in-memory secrets and a transport answering `status`/`body`.
  static func model(status: Int, body: String, seen: Seen) throws -> (
    S3ConnectionsModel, cleanup: () -> Void
  ) {
    let name = "fr.astrostack.tests.s3test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let store = S3ConnectionStore(defaults: defaults, secrets: .inMemory())
    let transport = HTTPTransport(
      send: { request in
        seen.append(request.url)
        return HTTPResponse(status: status, body: Data(body.utf8))
      },
      download: { _, _, _ in HTTPResponse(status: 500) })
    let model = S3ConnectionsModel(store: store, transport: { transport })
    return (model, { defaults.removePersistentDomain(forName: name) })
  }

  @Test("OK names the count; a 403 keeps S3's code and message as sent")
  func testReportsOKAndS3Error() async throws {
    for (status, body) in [(200, Self.listing), (403, Self.denied)] {
      let seen = Seen()
      let (model, cleanup) = try Self.model(status: status, body: body, seen: seen)
      defer { cleanup() }
      model.add()
      model.draft?.connection.name = "Captures"
      model.draft?.connection.endpoint = "http://127.0.0.1:9000"
      model.draft?.connection.pathStyle = true
      model.draft?.connection.accessKey = "minio"
      model.draft?.secret = "minio123"
      model.save()
      let id = try #require(model.connections.first?.id)
      model.testConnection = id
      model.testBucket = "astro"
      model.testPrefix = "M31/"

      await model.test()

      let url = try #require(seen.all.first)
      #expect(url.absoluteString.hasPrefix("http://127.0.0.1:9000/astro?"))
      #expect(url.query()?.contains("prefix=M31%2F") == true)
      if status == 200 {
        #expect(model.testResult == .ok(count: 2))
      } else {
        #expect(model.testResult == .failed("S3 403 AccessDenied: Access Denied."))
      }
    }
  }

  @Test("an unknown connection, or no bucket: refused before any request")
  func testRefusesWithoutSecretOrBucket() async throws {
    let seen = Seen()
    let (model, cleanup) = try Self.model(status: 200, body: Self.listing, seen: seen)
    defer { cleanup() }

    model.testConnection = UUID()
    model.testBucket = "astro"
    await model.test()
    #expect(model.testResult == .noConnection, "a removed connection is not « no secret »")

    model.testBucket = "  "
    #expect(!model.canTest)
    #expect(seen.all.isEmpty)
  }

  @Test("changing the connection, bucket or prefix clears the last answer; none chosen says so")
  func testResultFollowsTheChoice() async throws {
    let seen = Seen()
    let (model, cleanup) = try Self.model(status: 200, body: Self.listing, seen: seen)
    defer { cleanup() }

    await model.test()
    #expect(model.testResult == .noConnection)
    model.add()
    model.draft?.connection.name = "A"
    model.draft?.connection.endpoint = "https://s3.example.com"
    model.draft?.connection.accessKey = "AK"
    model.draft?.secret = "s"
    model.save()
    model.testBucket = "astro"
    await model.test()
    #expect(model.testResult == .ok(count: 2))

    model.testPrefix = "other/"
    #expect(model.testResult == nil, "an answer for another prefix is not this one's")
    await model.test()
    let id = try #require(model.connections.first?.id)
    model.edit(id)
    model.save()
    #expect(model.testResult == nil, "saved keys or endpoint: test again")
  }
}
