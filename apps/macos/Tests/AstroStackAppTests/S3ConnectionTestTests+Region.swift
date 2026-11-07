import AstroStackApp
import Foundation
import RemoteKit
import Testing

/// Card 0184: Settings › S3 connections › Test names the bucket's region when it is not the
/// connection's, and refuses a bucket name the connection cannot address, before any request.
extension S3ConnectionTestTests {
  /// A model whose transport answers `response`, the connection set to `endpoint`/`pathStyle`.
  static func model(
    answering response: HTTPResponse, endpoint: String, pathStyle: Bool, seen: Seen
  ) throws -> (S3ConnectionsModel, cleanup: () -> Void) {
    let name = "fr.astrostack.tests.s3region.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let store = S3ConnectionStore(defaults: defaults, secrets: .inMemory())
    let transport = HTTPTransport(
      send: { request in
        seen.append(request.url)
        return response
      },
      download: { _, _, _ in HTTPResponse(status: 500) })
    let model = S3ConnectionsModel(store: store, transport: { transport })
    model.add()
    model.draft?.connection.name = "Captures"
    model.draft?.connection.endpoint = endpoint
    model.draft?.connection.region = "us-east-1"
    model.draft?.connection.pathStyle = pathStyle
    model.draft?.connection.accessKey = "AKIAEXAMPLE"
    model.draft?.secret = "secret"
    model.save()
    model.testConnection = model.connections.first?.id
    return (model, { defaults.removePersistentDomain(forName: name) })
  }

  @Test("a bucket in another region: Test says which one")
  func testWrongRegionIsSaid() async throws {
    let seen = Seen()
    let (model, cleanup) = try Self.model(
      answering: HTTPResponse(status: 301, headers: ["x-amz-bucket-region": "eu-west-3"]),
      endpoint: "https://s3.amazonaws.com", pathStyle: false, seen: seen)
    defer { cleanup() }
    model.testBucket = "captures"

    await model.test()

    #expect(
      model.testResult
        == .failed("S3 301: bucket captures is in region eu-west-3, the connection says us-east-1"))
  }

  @Test("a dotted bucket over https with virtual-host addressing: refused, nothing sent")
  func testDottedBucketRefused() async throws {
    let seen = Seen()
    let (model, cleanup) = try Self.model(
      answering: HTTPResponse(status: 200), endpoint: "https://s3.amazonaws.com",
      pathStyle: false, seen: seen)
    defer { cleanup() }
    model.testBucket = "astro.data"

    await model.test()

    guard case .failed(let text) = model.testResult else {
      Issue.record("expected a refusal, got \(String(describing: model.testResult))")
      return
    }
    #expect(text.contains("astro.data"))
    #expect(text.contains("path-style"))
    #expect(seen.all.isEmpty)
  }
}
