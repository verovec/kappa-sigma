import AstroStackApp
import Foundation
import StackKit
import Testing

/// Card 0186: a master rebuilt from a bucket in Données checks its downloads against a listing,
/// as a run does — never bytes nothing listed.
@Suite("Données rebuild — a bucket master's frames checked against a listing")
struct RebuildStagerTests {
  @Test("the rebuild's stager expects what the bucket lists now, frames of this Mac aside")
  func testRebuildStagerExpectsTheListing() async throws {
    let store = RemoteObjectStore(
      bucket: "astro",
      list: { _ in [RemoteObjectStore.Object(key: "calib/d_1.fits", size: 7, etag: "e1")] },
      get: { _, _ in Data() })

    let stager = try await ImportPlanning.rebuildStager(
      stores: [store], paths: ["s3://astro/calib/d_1.fits", "/c/calib/d_2.fits"])

    #expect(stager.expected == ["s3://astro/calib/d_1.fits": "7|e1"])
  }
}
