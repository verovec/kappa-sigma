import Foundation
import StackKit
import TestSupport
import Testing

extension FrameStagerTests {
  @Test(
    "testStagedIdentitiesEqualListedIdentities: what a stage read is what the run listed",
    .scratchDirectory)
  func testStagedIdentitiesEqualListedIdentities() async throws {
    let root = try ScratchDirectory.url
    let bucket = FakeBucket(objects: [
      "M31/r_1.fits": Data("one".utf8), "M31/r_2.fits": Data("frame two".utf8),
    ])
    bucket.replace("M31/r_2.fits", with: Data("frame two, again".utf8))
    let paths = ["s3://astro/M31/r_1.fits", "s3://astro/M31/r_2.fits"]
    let stager = FrameStager(stores: [bucket.store])

    let listed = await stager.identities(of: paths)
    let staged = try await stager.stage(paths, into: root.appendingPathComponent("light_L"))

    // Both sides of a master's proof hash the same thing: its `.sig` is written from the bytes
    // a build downloaded, the reuse check compares it with what the next run lists.
    #expect(staged.identities == listed)
    #expect(listed["s3://astro/M31/r_2.fits"] == "16|e1", "a re-upload is a new ETag")
  }
}

// MARK: - A store that only answers `get`

extension FrameStagerTests {
  @Test(
    "testFallbackDownloadStagesTheFrame: a store without its own download still stages",
    .scratchDirectory)
  func testFallbackDownloadStagesTheFrame() async throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("light_L")
    let bucket = FakeBucket(objects: ["M31/r_1.fits": Data("one".utf8)], fetching: false)

    let staged = try await FrameStager(stores: [bucket.store]).stage(
      ["s3://astro/M31/r_1.fits"], into: folder)

    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["00001_r_1.fits"])
    #expect(staged.bytes == 3)
  }

  @Test(
    "testFallbackDownloadFailureLeavesNoPart: `get` written out leaves nothing when it fails",
    .scratchDirectory)
  func testFallbackDownloadFailureLeavesNoPart() async throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("light_L")
    let bucket = FakeBucket(objects: ["M31/r_1.fits": Data("one".utf8)], fetching: false)
    bucket.fail(true)

    await #expect(throws: (any Error).self) {
      try await FrameStager(stores: [bucket.store]).stage(["s3://astro/M31/r_1.fits"], into: folder)
    }

    let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    #expect(left.isEmpty, "no .part and no frame nothing read: \(left)")
  }
}
