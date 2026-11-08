import Foundation
import StackKit
import TestSupport
import Testing

extension RemoteCalibrationTests {
  /// A built bucket night and its masters as the library, as the next import sees them.
  static func builtLibrary() async throws -> (RemoteCalibration, MasterBuilder, [CalibrationMaster])
  {
    let night = try RemoteCalibration.make()
    let builder = try await night.builder()
    let built = try await builder.build(
      night.inventory, into: night.work.appendingPathComponent("masters"), work: night.work)
    return (night, builder, Self.library(built.masters))
  }

  @Test(
    "testPreviewReusesABucketMasterTheRunReuses: the sheet says what step 1 will do",
    .scratchDirectory)
  func testPreviewReusesABucketMasterTheRunReuses() async throws {
    let (night, builder, library) = try await Self.builtLibrary()

    // What the import sheet proposes, given what the scan listed — the same `size|etag` the
    // run lists before step 1.
    let candidates = CalibrationPreview.candidates(
      inventory: night.inventory, library: library, identities: builder.identities)

    #expect(
      candidates.allSatisfy { !$0.path.isEmpty },
      "no « will build » master while the run reuses every one (R2): \(candidates.count)")
    #expect(candidates.count == library.count)
  }

  @Test(
    "testPlanKeepsTheBucketIdentitiesWhenReplanned: a calibration choice never forgets them",
    .scratchDirectory)
  func testPlanKeepsTheBucketIdentitiesWhenReplanned() async throws {
    let (night, builder, library) = try await Self.builtLibrary()
    let plan = ImportPlan(
      inventory: night.inventory, library: library, request: ImportRequest(paths: ["/c"]),
      identities: builder.identities)

    var request = ImportRequest(paths: ["/c"])
    request.forceCalibration = true
    let replanned = await ImportPlanner.replanned(plan, request: request)

    #expect(replanned.identities == builder.identities)
    let statuses = replanned.calibration.flatMap(\.cells).map(\.status)
    #expect(
      !statuses.contains { if case .build = $0 { true } else { false } },
      "still reused after a replan: \(statuses)")
  }
}

// MARK: - A proof needs what the bucket answers now

extension RemoteCalibrationTests {
  @Test(
    "testRemoteFrameWithoutIdentityProvesNothing: a failed listing never proves a bucket master",
    .scratchDirectory)
  func testRemoteFrameWithoutIdentityProvesNothing() throws {
    let master = try ScratchDirectory.url.appendingPathComponent("master_BIAS.fits").path
    let paths = ["s3://astro/cal/b_1.fits", "s3://astro/cal/b_2.fits"]
    let listed = [paths[0]: "100|e1", paths[1]: "100|e2"]
    // A .sig signed by the keys alone — what a bucket master built before card 0181 holds.
    try PoolSignature.format(hash: PoolSignature.of(paths), frameCount: 2)
      .write(toFile: PoolSignature.sidecar(of: master), atomically: true, encoding: .utf8)

    #expect(
      !PoolSignature.proves(master: master, builtFrom: paths),
      "no identity: nothing says these are the bytes stacked")
    #expect(
      !PoolSignature.proves(master: master, builtFrom: paths, identities: [paths[0]: "100|e1"]),
      "one frame unanswered is enough to rebuild")
    #expect(!PoolSignature.proves(master: master, builtFrom: paths, identities: listed))

    try PoolSignature.format(hash: PoolSignature.of(paths, identities: listed), frameCount: 2)
      .write(toFile: PoolSignature.sidecar(of: master), atomically: true, encoding: .utf8)
    #expect(PoolSignature.proves(master: master, builtFrom: paths, identities: listed))
  }
}
