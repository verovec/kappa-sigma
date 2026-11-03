import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import Testing

/// Card 0169: the « Bucket S3 » half of the Import sheet browses a bucket one level at a time,
/// and a listing that fails says so instead of showing an empty bucket (R2).
@MainActor
@Suite("ImportBucketModel — browse a bucket one level at a time")
struct ImportBucketModelTests {
  static let connection = S3Connection(
    name: "Captures", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
    accessKey: "AK")

  /// A bucket whose levels are scripted, every listing recorded.
  @MainActor
  final class FakeBucket {
    var levels: [String: [String]] = [
      "": ["M31/", "M45/"],
      "M31/": ["M31/2026-10-18/", "M31/2026-10-19/"],
      "M31/2026-10-18/": [],
    ]
    var asked: [(bucket: String, prefix: String)] = []
    var failure: (any Error)?

    var browsing: ImportBucketModel.Browsing {
      { @MainActor _, bucket, prefix in
        self.asked.append((bucket, prefix))
        if let failure = self.failure { throw failure }
        return self.levels[prefix] ?? []
      }
    }
  }

  static func model(_ fake: FakeBucket, bucket: String = "astro") -> ImportBucketModel {
    let model = ImportBucketModel(connections: [connection], browsing: fake.browsing)
    model.connectionID = connection.id
    model.bucket = bucket
    return model
  }

  @Test("the folders of a level, then one level down and back up")
  func testBrowseOneLevelAtATime() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)

    model.browse()
    await model.settled()
    #expect(model.folders == ["M31/", "M45/"])
    #expect(model.prefix.isEmpty && !model.isBrowsing)

    model.enter("M31/")
    await model.settled()
    #expect(model.prefix == "M31/" && model.folders == ["M31/2026-10-18/", "M31/2026-10-19/"])

    model.enter("M31/2026-10-18/")
    await model.settled()
    #expect(model.folders.isEmpty, "a night holds frames, not folders")

    model.up()
    await model.settled()
    #expect(model.prefix == "M31/" && model.folders == ["M31/2026-10-18/", "M31/2026-10-19/"])

    model.up()
    await model.settled()
    #expect(model.prefix.isEmpty && model.folders == ["M31/", "M45/"])
    #expect(fake.asked.map(\.prefix) == ["", "M31/", "M31/2026-10-18/", "M31/", ""])
    #expect(fake.asked.allSatisfy { $0.bucket == "astro" })
  }

  @Test("a listing that fails says so and keeps the folders already shown")
  func testFailedListingKeepsTheLastFolders() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    model.browse()
    await model.settled()

    fake.failure = S3Error.service(
      status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
    model.enter("M31/")
    await model.settled()

    #expect(model.error != nil, "the failure is shown, not swallowed")
    #expect(
      model.folders == ["M31/", "M45/"],
      "an empty list would read as « this prefix holds nothing » (R2)")
    #expect(!model.isBrowsing)
  }

  @Test("the target is the connection, the bucket and the prefix, spelled as the project does")
  func testTargetSpelling() throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    model.enter("M31/2026-10-18/")

    let target = try #require(model.target)

    #expect(target.bucket == "astro" && target.prefix == "M31/2026-10-18/")
    #expect(target.path == "s3://astro/M31/2026-10-18")
    #expect(target.path == ProjectSource.remotePath(bucket: "astro", prefix: target.prefix))
  }

  @Test(
    "no connection or no bucket is no target: nothing is scanned on a guess",
    arguments: [
      (true, ""), (false, "astro"), (false, ""),
    ])
  func testTargetNeedsBoth(hasConnection: Bool, bucket: String) {
    let fake = FakeBucket()
    let model = ImportBucketModel(connections: [Self.connection], browsing: fake.browsing)
    model.connectionID = hasConnection ? Self.connection.id : nil
    model.bucket = bucket

    #expect(model.target == nil)
  }

  @Test("a new bucket starts over: the level browsed in the previous one is not claimed for it")
  func testChangingTheBucketStartsOver() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    model.browse()
    await model.settled()
    model.enter("M31/")
    await model.settled()
    #expect(model.prefix == "M31/" && !model.folders.isEmpty && model.hasListed)

    model.bucket = "other"

    #expect(model.prefix.isEmpty, "back to the root of the bucket just named")
    #expect(model.folders.isEmpty && !model.hasListed, "nothing was read of it yet")
    #expect(model.target?.bucket == "other")
  }

  @Test("choosing another connection starts over too")
  func testChangingTheConnectionStartsOver() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    model.browse()
    await model.settled()
    #expect(model.hasListed)

    model.connectionID = UUID()

    #expect(model.folders.isEmpty && !model.hasListed && model.prefix.isEmpty)
  }

  @Test("a level is « empty » only once a listing answered")
  func testEmptyLevelIsMeasured() async throws {
    let fake = FakeBucket()
    let model = Self.model(fake)
    #expect(!model.hasListed, "before any browse: nothing read")

    fake.failure = CocoaError(.fileReadNoPermission)
    model.browse()
    await model.settled()
    #expect(!model.hasListed, "a listing that failed read nothing either")

    fake.failure = nil
    model.enter("M31/2026-10-18/")
    await model.settled()
    #expect(model.hasListed && model.folders.isEmpty, "that level truly holds no folder")
  }
}
