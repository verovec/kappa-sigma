import Foundation
import RemoteKit
import Testing

/// Card 0186: Browse needs a level's folders alone; a folder of thousands of frames is paged
/// through without its objects being kept.
@Suite("S3Client — one level's sub-prefixes alone")
struct S3ClientPrefixTests {
  @Test("listPrefixes answers every page's folders and keeps none of the keys")
  func testPrefixesDropObjectsPerPage() async throws {
    let fake = Fake { _, call in
      call == 0
        ? .make(
          200,
          S3ClientTests.level(
            [("M31/info.txt", 12, "e1")], folders: ["M31/2026-10-18/"], truncated: true,
            next: "tok"))
        : .make(
          200,
          S3ClientTests.level(
            [("M31/notes.txt", 3, "e2")], folders: ["M31/2026-10-19/"], truncated: false,
            next: nil))
    }

    let prefixes = try await fake.client().listPrefixes(
      bucket: "astro", prefix: "M31/", delimiter: "/")

    #expect(prefixes == ["M31/2026-10-18/", "M31/2026-10-19/"])
    #expect(await fake.requests.map { $0.query("delimiter") } == ["/", "/"])
  }
}
