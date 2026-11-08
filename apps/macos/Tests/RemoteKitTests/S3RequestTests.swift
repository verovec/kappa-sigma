import Foundation
import RemoteKit
import Testing

@Suite("S3 requests address the bucket and encode the key once")
struct S3RequestTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let label: String
    let endpoint: String
    let addressing: S3Endpoint.Addressing
    let bucket: String
    let key: String
    let query: [SignableRequest.QueryItem]
    let url: String
    let host: String
    var testDescription: String { label }
  }

  static let rows: [Row] = [
    Row(
      label: "AWS virtual host", endpoint: "https://s3.eu-west-3.amazonaws.com",
      addressing: .virtualHost, bucket: "captures", key: "M31/Light_001.fits", query: [],
      url: "https://captures.s3.eu-west-3.amazonaws.com/M31/Light_001.fits",
      host: "captures.s3.eu-west-3.amazonaws.com"),
    Row(
      label: "MinIO path-style with a port", endpoint: "http://127.0.0.1:9000",
      addressing: .pathStyle, bucket: "astro", key: "M31/Light_001.fits", query: [],
      url: "http://127.0.0.1:9000/astro/M31/Light_001.fits", host: "127.0.0.1:9000"),
    Row(
      label: "key with spaces, UTF-8 and reserved characters", endpoint: "http://minio.local:9000",
      addressing: .pathStyle, bucket: "astro", key: "Nébuleuse/nuit 1/a+b=c.fits", query: [],
      url: "http://minio.local:9000/astro/N%C3%A9buleuse/nuit%201/a%2Bb%3Dc.fits",
      host: "minio.local:9000"),
    Row(
      label: "an empty path segment kept as written (AWS accepts `a//b`, MinIO refuses it)",
      endpoint: "https://s3.eu-west-3.amazonaws.com", addressing: .virtualHost,
      bucket: "captures", key: "M31//Light_001.fits", query: [],
      url: "https://captures.s3.eu-west-3.amazonaws.com/M31//Light_001.fits",
      host: "captures.s3.eu-west-3.amazonaws.com"),
    Row(
      label: "listing a prefix, path-style", endpoint: "http://127.0.0.1:9000",
      addressing: .pathStyle, bucket: "astro", key: "",
      query: [.init("prefix", "M31/nuit 1/"), .init("list-type", "2")],
      url: "http://127.0.0.1:9000/astro?list-type=2&prefix=M31%2Fnuit%201%2F",
      host: "127.0.0.1:9000"),
    Row(
      label: "listing, virtual host", endpoint: "https://s3.amazonaws.com",
      addressing: .virtualHost, bucket: "captures", key: "", query: [.init("list-type", "2")],
      url: "https://captures.s3.amazonaws.com/?list-type=2", host: "captures.s3.amazonaws.com"),
    Row(
      label: "default port dropped", endpoint: "https://s3.fr-par.scw.cloud:443/",
      addressing: .pathStyle, bucket: "astro", key: "k", query: [.init("uploads", "")],
      url: "https://s3.fr-par.scw.cloud/astro/k?uploads=", host: "s3.fr-par.scw.cloud"),
    Row(
      label: "IPv6 literal keeps its brackets", endpoint: "http://[::1]:9000",
      addressing: .pathStyle, bucket: "astro", key: "k", query: [],
      url: "http://[::1]:9000/astro/k", host: "[::1]:9000"),
  ]

  @Test("URL and signed host per addressing style", arguments: rows)
  func testPathStyleAndVirtualHost(row: Row) throws {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: row.endpoint)), region: "us-east-1",
      addressing: row.addressing)
    let request = S3Request(method: "GET", bucket: row.bucket, key: row.key, query: row.query)

    let http = try request.prepared(
      endpoint: endpoint, signer: SigV4(credentials: Fake.credentials, region: "us-east-1"),
      date: Fake.date)

    #expect(http.url.absoluteString == row.url)
    #expect(http.headers["host"] == row.host)
    #expect(http.headers["x-amz-date"] == "20261101T120000Z")
    #expect(http.headers["x-amz-content-sha256"] == Data().sha256Hex)
    let authorization = try #require(http.headers["authorization"])
    #expect(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=AKFAKE/20261101/us-east-1/s3/"))
    #expect(authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date,"))
  }

  @Test("A body is hashed into x-amz-content-sha256 and carried as is")
  func testPrepared_bodyHash() throws {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
      addressing: .pathStyle)
    let body = Data("hello".utf8)
    let request = S3Request(method: "PUT", bucket: "b", key: "k", body: body)

    let http = try request.prepared(
      endpoint: endpoint, signer: SigV4(credentials: Fake.credentials, region: "us-east-1"),
      date: Fake.date)

    #expect(http.body == body)
    #expect(
      http.headers["x-amz-content-sha256"]
        == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
  }

  @Test("An endpoint needs an http(s) scheme and a host", arguments: ["ftp://h", "h:9000", "/x"])
  func testEndpoint_rejectsInvalidURL(text: String) throws {
    let url = try #require(URL(string: text))
    #expect(throws: S3Error.self) {
      try S3Endpoint(url: url, region: "us-east-1", addressing: .pathStyle)
    }
  }
}
