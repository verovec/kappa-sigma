import AstroStackApp
import Foundation
import Testing

/// The bucket field takes a pasted location, the path is walked by its crumbs, and the form reads
/// its level on its own when it opens.
extension ImportBucketModelTests {
  @Test(
    "what the bucket field holds: a bare name, or a location with the prefix it names",
    arguments: [
      ("astrophoto", "astrophoto", nil),
      ("  astrophoto ", "astrophoto", nil),
      ("s3://astrophoto", "astrophoto", ""),
      ("s3://astrophoto/", "astrophoto", ""),
      ("s3://astrophoto/astro/2026_09_15/Orion/L/", "astrophoto", "astro/2026_09_15/Orion/L/"),
      ("S3://astrophoto/astro", "astrophoto", "astro/"),
      ("astrophoto/astro//Orion", "astrophoto", "astro/Orion/"),
      ("", "", nil),
    ] as [(String, String, String?)])
  func testLocation(text: String, bucket: String, prefix: String?) {
    let read = ImportBucketModel.location(text)
    #expect(read.bucket == bucket)
    #expect(read.prefix == prefix)
  }

  @Test("a pasted location is scanned as it reads, and « Browse » lists the prefix it names")
  func testPastedLocation() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake, bucket: "s3://astro/M31/")

    let target = try #require(model.target)
    #expect(target.bucket == "astro" && target.prefix == "M31/", "scannable without a browse")

    model.browse()
    await model.settled()
    #expect(model.bucket == "astro", "the field keeps the bucket's name")
    #expect(model.prefix == "M31/")
    #expect(model.folders == ["M31/2026-10-18/", "M31/2026-10-19/"])
    #expect(fake.asked.map(\.bucket) == ["astro"] && fake.asked.map(\.prefix) == ["M31/"])
  }

  @Test("the crumbs lead from the bucket to the level browsed, and each one goes back to its own")
  func testCrumbs() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    #expect(model.crumbs.map(\.name) == ["astro"])

    model.enter("M31/")
    model.enter("M31/2026-10-18/")
    await model.settled()
    #expect(model.crumbs.map(\.name) == ["astro", "M31", "2026-10-18"])
    #expect(model.crumbs.map(\.prefix) == ["", "M31/", "M31/2026-10-18/"])

    model.enter(model.crumbs[1].prefix)
    await model.settled()
    #expect(model.prefix == "M31/" && model.folders.count == 2)
  }

  @Test("the form reads its level once on its own: not again, and not over a failure")
  func testBrowseIfUnread() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)

    model.browseIfUnread()
    await model.settled()
    model.browseIfUnread()
    await model.settled()
    #expect(fake.asked.count == 1 && model.folders == ["M31/", "M45/"])

    let failing = FakeBucket()
    failing.failure = CocoaError(.fileReadUnknown)
    let failed = Self.model(failing)
    failed.browseIfUnread()
    await failed.settled()
    failed.browseIfUnread()
    await failed.settled()
    #expect(failing.asked.count == 1 && failed.error != nil, "a failure is not retried unasked")
  }
}
