import Foundation
import RemoteKit
import Synchronization
import TestSupport
import Testing

@Suite("RemoteKit helpers: file sizes, XML, redirects")
struct RemoteKitInternalsTests {
  @Test("A file's size is read through a symbolic link", .scratchDirectory)
  func testFileDigest_sizeFollowsLinks() throws {
    let folder = try ScratchDirectory.url
    let file = folder.appendingPathComponent("frame.fits")
    try Data(count: 100_000).write(to: file)
    let link = folder.appendingPathComponent("link.fits")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

    #expect(try FileDigest.size(link) == 100_000)
  }

  @Test("Whitespace before the XML declaration (S3 keep-alive) is skipped")
  func testXMLNode_leadingWhitespace() throws {
    let body = "\n  \n<?xml version=\"1.0\"?><R><ETag>e</ETag></R>"

    let root = try XMLNode.parse(Data(body.utf8))

    #expect(root.name == "R")
    #expect(root.text("ETag") == "e")
  }

  @Test("Malformed or empty XML is an invalidResponse")
  func testXMLNode_malformed() {
    #expect(throws: S3Error.self) { try XMLNode.parse(Data("<R><a></R>".utf8)) }
    #expect(throws: S3Error.self) { try XMLNode.parse(Data()) }
  }

  @Test("The live transport's session delegate refuses every redirect")
  func testRedirectRefusal() throws {
    let url = try #require(URL(string: "https://astro.s3.amazonaws.com/k"))
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let response = try #require(
      HTTPURLResponse(url: url, statusCode: 301, httpVersion: nil, headerFields: nil))
    let followed = Mutex<URLRequest?>(URLRequest(url: url))

    RedirectRefusal().urlSession(
      session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: url),
      completionHandler: { next in followed.withLock { $0 = next } })

    #expect(followed.withLock { $0 } == nil)
  }
}
